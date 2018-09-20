#!/usr/bin/python

from bluepy.btle import Scanner, DefaultDelegate, BTLEException
from bluepy import btle
import threading
import queue
import uuid
import time
import binascii
import traceback
import logging
import subprocess
import struct
import socket
import sys
import os
import json
import datetime


FORMAT = '%(asctime)-15s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger()
logger.setLevel(logging.DEBUG)

def reverse_uuid(service_uuid):
    if len(service_uuid) == 4:
        return service_uuid[2:4] + service_uuid[0:2]
    return uuid.UUID(bytes="".join([uuid.UUID(service_uuid).bytes[15-i] for i in range(16)])).hex

# Define service and characteristic UUIDs.

class DeviceManager(object):
    def __init__(self, service_and_char_uuids, thread_class):
        self.threads_by_addr = {}
        self.threads_by_name = {}
        self.service_and_char_uuids = service_and_char_uuids
        self.required_services = set([reverse_uuid(s[0]) for s in service_and_char_uuids])
        self.thread_class = thread_class
        self.coordinator = None


    def all_broadcasters(self):
        return self.threads_by_addr.values()


    def set_coordinator(self, coordinator):
        self.coordinator = coordinator


    def should_connect_to(self, device, device_name):
        return True


    def found_devices(self, devices):
        # Check if everything is OK
        for addr in self.threads_by_addr.keys():   # .keys() creates a copy and avoids error due to removing key
            t = self.threads_by_addr[addr]
            if not t.is_alive():
                if self.coordinator is not None:
                    self.coordinator.device_disconnected(t)
                del self.threads_by_name[t.name]
                del self.threads_by_addr[addr]
                logger.debug("Device %s thread died... Removing", t.name)

        for dev in devices:
            scan_data = dev.getScanData()
            services = set([s[2] for s in scan_data if s[0] in [3, 6, 7]])

            name = dev.getValueText(9) or dev.getValueText(8)
            if (name is not None and
                self.should_connect_to(dev, name) and
                self.required_services <= services and
                dev.addr not in self.threads_by_addr and 
                name not in self.threads_by_name):
                try:
                    logger.debug("Found device %s type %s", dev.addr, type(self))
                    t = self.thread_class(self, dev, name, self.service_and_char_uuids)
                    logger.debug("Connected to %s (%s)", dev.addr, t.name)
                    self.threads_by_addr[dev.addr] = t
                    self.threads_by_name[name] = t
                    if self.coordinator is not None:
                        self.coordinator.device_connected(t)
                        # Send all currently known states
                        for s in self.coordinator.current_state.values():
                            t.broadcast_received(s)

                except Exception, e:
                    logger.debug("Exception connecting to %s: %s", dev.addr, e)


class NotificationDelegate(DefaultDelegate):
    def __init__(self):
        DefaultDelegate.__init__(self)
        self.last_data = None


    def handleNotification(self, cHandle, data):
        self.last_data = (cHandle, data)


class BroadcastMessage(object):
    def __init__(self, source, destination, prop, value):
        self.source = source
        self.destination = destination
        self.prop = prop
        self.value = value
        self.key = "%s:%s" % (prop, source)
        self.ts = time.time()


    def __str__(self):
        return "Broadcast from %s to %s, %s = %s" % (self.source, self.destination, self.prop, self.value)

        

class SenderReceiver(object):
    def __init__(self, name):
        self.name = name
        self.broadcast_messages = queue.Queue()


    def found_devices(self, devices):
        pass


    def broadcast_received(self, broadcast):
        pass


    def add_broadcast(self, destination, prop, value):
        self.broadcast_messages.put(BroadcastMessage(self.name, destination, prop, value))


    def all_broadcasters(self):
        return [self]


    def set_coordinator(self, coordinator):
        pass



class DeviceThread(SenderReceiver):
    def __init__(self, manager, dev, name, service_and_char_uuids):
        """ Constructor
        """
        SenderReceiver.__init__(self, name)

        self.manager = manager
        self.dev = dev
        self.service_and_char_uuids = service_and_char_uuids

        self.addr = dev.addr
        self.name = name

        self.delegate = NotificationDelegate()
        self.peripheral = btle.Peripheral()
        self.peripheral.setDelegate(self.delegate)
        self.peripheral.connect(self.dev)

        # logger.debug("services %s", [s.uuid.getCommonName() for s in self.peripheral.getServices()])
        self.services = [self.peripheral.getServiceByUUID(s[0]) for s in service_and_char_uuids]
        self.characteristics = {}
        for i, s in enumerate(service_and_char_uuids):
            service_uuid = s[0]
            service = self.services[i]
            self.characteristics[service_uuid] = [service.getCharacteristics(uuid)[0] for uuid in s[1:]]
        
        self.commands = queue.Queue()
        
        self.before_thread()
    
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True                            # Daemonize thread
        self.thread.start()                                  # Start the execution

        
    def run(self):
        """ Method that runs forever """

        while True:
            try:
                if self.peripheral.waitForNotifications(0.1):
                    # handleNotification() was called
                    self.received_data(self.delegate.last_data[0], self.delegate.last_data[1])
                else:
                    self.no_data_received()

            except BTLEException, e:
                if e.code == BTLEException.DISCONNECTED:
                    self.peripheral.disconnect()
                    logger.debug("%s disconnected", self.name)
                else:
                    logger.debug("BTLEException: %s\n%s", e, traceback.format_exc())
                break

            except Exception, e:
                logger.debug("Exception: %s\n%s", e, traceback.format_exc())

            try:
                command = self.commands.get(False)
                command()
                self.commands.task_done()
            except queue.Empty:
                pass
            except Exception, e:
                logger.debug("Exception: %s\n%s", e, traceback.format_exc())


    def start_notifications(self, characteristic):
        # From https://stackoverflow.com/a/42703501/754013
        self.peripheral.writeCharacteristic(characteristic.valHandle + 1, "\x01\x00")


    def is_alive(self):
        return self.thread.is_alive()
        
        
    def before_thread(self):
        # Do something in subclasses
        pass
    
    
    def received_data(self, cHandle, data):
        # Do something in subclasses
        pass

        
    def no_data_received(self):
        # Just in case a subclass wants to do something about it.
        pass
        
        
    def add_command(self, command):
        self.commands.put(command)


class BeanManager(DeviceManager):

    def __init__(self):
        SERVICE_UUID = 'a495ff10-c5b1-4b44-b512-1370f02d74de'
        TX_CHAR_UUID = 'a495ff11-c5b1-4b44-b512-1370f02d74de'

        DeviceManager.__init__(self, [[SERVICE_UUID, TX_CHAR_UUID]], BeanThread)


    def should_connect_to(self, device, device_name):
        return device_name != "AgnesInside"


class BeanThread(DeviceThread):

    def before_thread(self):
        self.received_uart_data = queue.Queue()
        service_uuid = self.service_and_char_uuids[0][0]
        self.tx_characteristic = self.characteristics[service_uuid][0]
        self.start_notifications(self.tx_characteristic)
        self.next_temp_read = datetime.datetime.now()


    def no_data_received(self):
        if datetime.datetime.now() > self.next_temp_read:
            self.next_temp_read = datetime.datetime.now() + datetime.timedelta(seconds=30)
            self.add_command(lambda: self.tx_characteristic.write(binascii.unhexlify("a0020020115e6d")))


    def received_data(self, cHandle, data):
        data_type = ord(data[4])
        if data_type == 0x91:
            temperature = 32.0 + float(ord(data[5])) * 9.0 / 5.0
            self.add_command(lambda: self.tx_characteristic.write(binascii.unhexlify("a0020020107f7d")))
            self.add_broadcast(None, "Temperature", temperature)
        elif data_type == 0x90:
            x = struct.unpack('<h', data[5:7])[0]
            y = struct.unpack('<h', data[7:9])[0]
            z = struct.unpack('<h', data[9:11])[0]
            self.add_broadcast(None, "Accelerometer", (x, y, z))
        else:
            logger.error("Unkown type: %d (%s)" % (data_type, binascii.hexlify(data)))
            


class UARTManager(DeviceManager):

    def __init__(self):
        SERVICE_UUID = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E'
        TX_CHAR_UUID = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E'
        RX_CHAR_UUID = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E'

        DeviceManager.__init__(self, [[SERVICE_UUID, TX_CHAR_UUID, RX_CHAR_UUID]], UARTThread)
        

class UARTThread(DeviceThread):

    def before_thread(self):
        self.received_uart_data = queue.Queue()
        service_uuid = self.service_and_char_uuids[0][0]
        self.tx_characteristic = self.characteristics[service_uuid][0]
        self.rx_characteristic = self.characteristics[service_uuid][1]
        self.start_notifications(self.rx_characteristic)


    def received_data(self, cHandle, data):
        # Maybe use this for something..
        # self.received_uart_data.put(data)
        pass

        
    def write(self, data):
        """Write a string of data to the UART device."""
        self.add_command(lambda: self.tx_characteristic.write(data))


    def send_command(self, command):
        logger.debug("Sending command %s to %s", binascii.hexlify(command), self.name)
        full_command = "!" + chr(len(command) + 3) + command
        checksum = 0
        for c in full_command:
            checksum += ord(c)
        checksum = (checksum & 0xFF) ^ 0xFF
        full_command += chr(checksum)
        self.write(full_command)


    def broadcast_received(self, broadcast):
        if broadcast.destination is not None and broadcast.destination.startswith("Light:") and broadcast.prop == "Mode":
            strip = broadcast.destination[-1]
        
            mode = broadcast.value[0]
            if mode not in "CRT":
                logger.debug("Unknown mode: %s", mode)
                return

            color = binascii.unhexlify(broadcast.value[1:])
            self.send_command(mode + strip + color)
        elif broadcast.prop == "Speed" and broadcast.source == "Socket" and broadcast.value > 10:
            # Turn light off
            self.send_command("CI\x00\x00\x00\x00")
            self.send_command("CO\x00\x00\x00\x00")


    def read(self, timeout_sec=None):
        """Block until data is available to read from the UART.  Will return a
        string of data that has been received.  Timeout_sec specifies how many
        seconds to wait for data to be available and will block forever if None
        (the default).  If the timeout is exceeded and no data is found then
        None is returned.
        """
        try:
            read_data = self.received_uart_data.get(timeout=timeout_sec)
            self.received_uart_data.task_done()
            return read_data
        except queue.Empty:
            # Timeout exceeded, return None to signify no data received.
            return None


class ControllerManager(DeviceManager):

    def __init__(self):
        SERVICE_UUID = '12345678-1234-5678-1234-56789abc0010'
        COMMAND_CHAR_UUID = '12345679-1234-5678-1234-56789abc0010'
        DEVICES_CHAR_UUID = '1234567a-1234-5678-1234-56789abc0010'

        DeviceManager.__init__(self, [[SERVICE_UUID, COMMAND_CHAR_UUID, DEVICES_CHAR_UUID]], ControllerThread)
        

class ControllerThread(DeviceThread):

    def before_thread(self):
        service_uuid = self.service_and_char_uuids[0][0]
        self.command_characteristic = self.characteristics[service_uuid][0]
        self.devices_characteristic = self.characteristics[service_uuid][1]
        self.start_notifications(self.command_characteristic)


    def received_data(self, cHandle, data):
        if cHandle == self.command_characteristic.getHandle():
            destination = data[0]
            if destination == "L":
                strip = data[1]
                value = data[2:]
                self.add_broadcast("Light:%s" % strip, "Mode", value)
            elif destination == "P":
                self.add_broadcast("Locks", "State", data[1])
            elif destination == "T":
                self.add_broadcast("Thermostat", "On", int(data[2]))
                self.add_broadcast("Thermostat", "Target", int(data[3:], 16))
            else:
                logger.info("Unknown destination: %s" % data)


    def broadcast_received(self, broadcast):
        if broadcast.destination == None and broadcast.prop == "Devices":
            self.add_command(lambda: self.devices_characteristic.write("Dv" + broadcast.value))
        elif broadcast.destination == None and broadcast.prop == "Temperature" and broadcast.source == "Thermostat":
            self.add_command(lambda: self.devices_characteristic.write("Ti%.0f" % (broadcast.value * 10)))
        elif broadcast.destination == None and broadcast.prop == "Temperature" and broadcast.source == "AgnesOutside":
            self.add_command(lambda: self.devices_characteristic.write("To%.0f" % (broadcast.value * 10)))
        elif broadcast.destination == None and broadcast.prop == "Humidity" and broadcast.source == "Thermostat":
            self.add_command(lambda: self.devices_characteristic.write("Hm%.0f" % (broadcast.value * 10)))
        elif broadcast.destination == None and broadcast.prop == "On" and broadcast.source == "Thermostat":
            self.add_command(lambda: self.devices_characteristic.write("To%d" % broadcast.value))
        elif broadcast.destination == None and broadcast.prop == "Target" and broadcast.source == "Thermostat":
            self.add_command(lambda: self.devices_characteristic.write("Tt%.0f" % (broadcast.value * 10)))


class ThermostatManager(DeviceManager):

    def __init__(self):
        SERVICE_UUID = '1234'
        TEMP_CHAR_UUID = '1235'
        HUMID_CHAR_UUID = '1236'
        ONOFF_CHAR_UUID = '1237'
        TARGET_CHAR_UUID = '1238'

        DeviceManager.__init__(self, [[SERVICE_UUID, TEMP_CHAR_UUID, HUMID_CHAR_UUID, ONOFF_CHAR_UUID, TARGET_CHAR_UUID]], ThermostatThread)
        

class ThermostatThread(DeviceThread):

    def before_thread(self):
        service_uuid = self.service_and_char_uuids[0][0]
        self.temperature = None
        self.humidity = None
        self.onoff = None
        self.target = None
        self.temperature_characteristic = self.characteristics[service_uuid][0]
        self.humidity_characteristic = self.characteristics[service_uuid][1]
        self.onoff_characteristic = self.characteristics[service_uuid][2]
        self.target_characteristic = self.characteristics[service_uuid][3]
        self.start_notifications(self.temperature_characteristic)
        self.start_notifications(self.humidity_characteristic)
        self.start_notifications(self.onoff_characteristic)
        self.start_notifications(self.target_characteristic)
        self.onoff = int(struct.unpack('B', self.onoff_characteristic.read())[0])
        self.target = float(struct.unpack('<h', self.target_characteristic.read())[0]) / 10
        self.add_broadcast(None, "On", self.onoff)
        self.add_broadcast(None, "Target", self.target) 


    def received_data(self, cHandle, data):
        if cHandle == self.temperature_characteristic.getHandle():
            self.temperature = float(struct.unpack('<h', data)[0]) / 10
            self.add_broadcast(None, "Temperature", self.temperature)
        elif cHandle == self.humidity_characteristic.getHandle():
            self.humidity = float(struct.unpack('<h', data)[0]) / 10
            self.add_broadcast(None, "Humidity", self.humidity)
        elif cHandle == self.onoff_characteristic.getHandle():
            self.onoff = int(struct.unpack('B', data)[0])
            self.add_broadcast(None, "On", self.onoff)
        elif cHandle == self.target_characteristic.getHandle():
            self.target = float(struct.unpack('<h', data)[0]) / 10
            self.add_broadcast(None, "Target", self.target)
        else:
            logger.debug("Unknown handle %d", cHandle)


    def broadcast_received(self, broadcast):
        if broadcast.destination == "Thermostat" and broadcast.prop == "On":
            onoff = broadcast.value
            logger.debug("Setting onoff to %d", onoff)
            self.add_command(lambda: self.onoff_characteristic.write('\x01' if onoff else '\x00'))
        elif broadcast.destination == "Thermostat" and broadcast.prop == "Target":
            temp = broadcast.value
            logger.debug("Setting temp to %d", temp)
            self.add_command(lambda: self.target_characteristic.write(struct.pack('<h', temp)))
        elif broadcast.prop == "Speed" and broadcast.source == "Socket" and broadcast.value > 10:
            # Turn thermostat off
            self.add_command(lambda: self.onoff_characteristic.write('\x00'))


class PIManager(SenderReceiver):
    def __init__(self):
        SenderReceiver.__init__(self, "Pi")
        subprocess.call("gpio write 0 0", shell=True)
        subprocess.call("gpio write 7 0", shell=True)
        subprocess.call("gpio mode 0 out", shell=True)
        subprocess.call("gpio mode 7 out", shell=True)


    def broadcast_received(self, broadcast):
        if broadcast.destination == "Locks" and broadcast.prop == "State":
            logger.debug("Pi received command %s", broadcast.value)
            
            port = 7 if broadcast.value == "L" else 0
            subprocess.call("gpio mode %d out" % port, shell=True)
            subprocess.call("gpio write %d 1" % port, shell=True)
            time.sleep(0.3)
            subprocess.call("gpio write %d 0" % port, shell=True)
            time.sleep(0.2)
            subprocess.call("gpio write %d 1" % port, shell=True)
            time.sleep(0.3)
            subprocess.call("gpio write %d 0" % port, shell=True)


class SocketManager(SenderReceiver):
    def __init__(self):
        SenderReceiver.__init__(self, "Socket")
        server_address = '/tmp/vantomation.socket'

        # Make sure the socket does not already exist
        try:
            os.unlink(server_address)
        except OSError:
            if os.path.exists(server_address):
                raise

        # Create a UDS socket
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(server_address)

        # Listen for incoming connections
        self.sock.listen(1)
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True                            # Daemonize thread
        self.thread.start()                                  # Start the execution


    def run(self):
        """ Method that runs forever """
        while True:
            # Wait for a connection
            connection, client_address = self.sock.accept()
            try:
                logger.debug("connection from %s", client_address)

                # Receive the data in small chunks and retransmit it
                past_data = ""
                while True:
                    data = connection.recv(256)
                    if data == '':
                        continue
                    past_data += data
                    lines = past_data.split("\n")
                    past_data = lines[-1]
                    for command in lines[0:-1]:
                        if command[0] == "L":
                            components = command[1:].split(',')
                            self.add_broadcast(None, "Location", (float(components[0]) / 10000, float(components[1]) / 10000))
                        elif command[0] == "A":
                            components = command[1:].split(',')
                            self.add_broadcast(None, "Altitude", int(components[0]))
                            self.add_broadcast(None, "Speed", int(components[1]))
                            self.add_broadcast(None, "Heading", int(components[2]))
                            
            finally:
                # Clean up the connection
                connection.close()


class StateManager(SenderReceiver):
    def __init__(self):
        SenderReceiver.__init__(self, "StateManager")
        self.current_state = {}


    def broadcast_received(self, broadcast):
        if broadcast.destination is None:
            self.current_state = self.coordinator.current_state
            self.dump_state()


    def set_coordinator(self, coordinator):
        self.coordinator = coordinator
        self.current_state = self.coordinator.current_state
        self.dump_state()


    def dump_state(self):
        state = {k: {'ts': v.ts, 'value': v.value} for (k, v) in self.current_state.iteritems()}
        state_file = open("/tmp/vantomation.state.json.temp", "w+")
        state_file.write(json.dumps(state))
        state_file.close()
        os.rename("/tmp/vantomation.state.json.temp", "/tmp/vantomation.state.json")


class WiFiManager(SenderReceiver):
    def __init__(self):
        SenderReceiver.__init__(self, "Wifi")
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True
        self.thread.start()


    def run(self):
        """ Method that runs forever """
        time.sleep(2)   # Give some time for others to start working too...
        while True:
            try:
                status = subprocess.check_output('wpa_cli -i wlan1 status', shell=True)
                status = {l.split('=', 1)[0]: l.split('=', 1)[1] for l in status.splitlines()}
                self.add_broadcast(None, "State", status.get('wpa_state'))
                self.add_broadcast(None, "SSID", status.get('ssid'))
                self.add_broadcast(None, "IP", status.get('ip_address'))

                scan = subprocess.check_output('wpa_cli -i wlan1 scan_results', shell=True)
                scan = [l.split('\t') for l in scan.splitlines()[1:]]
                self.add_broadcast(None, "Scan", scan)

            except Exception, e:
                logger.debug("Exception: %s\n%s", e, traceback.format_exc())

            time.sleep(10)


class Coordinator(SenderReceiver):

    def __init__(self, device_managers):
        SenderReceiver.__init__(self, "Coordinator")
        self.connected_devices = set()

        self.devices = {
            'L': 'fd:6e:55:f0:de:06',
            'T': 'eb:cc:ee:35:55:c0',
            'O': '98:7b:f3:59:1e:d4',
            'I': '98:7b:f3:5a:d2:3f',
        }
        
        self.devices_by_addr = {v: k for (k, v) in self.devices.iteritems()}
        
        self.current_state = {}
        
        self.device_managers = device_managers
        for manager in device_managers:
            manager.set_coordinator(self)

        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True                            # Daemonize thread
        self.thread.start()                                  # Start the execution
        

    def device_connected(self, thread):
        self.connected_devices.add(thread.addr)
        self.update_connected_devices()


    def device_disconnected(self, thread):
        self.connected_devices.remove(thread.addr)
        self.update_connected_devices()


    def update_connected_devices(self):
        connected = "!" + ("".join(sorted([self.devices_by_addr[addr] for addr in self.connected_devices if addr in self.devices_by_addr])))
        self.add_broadcast(None, "Devices", connected)


    def run(self):
        """ Method that runs forever """

        while True:
            broadcasters = [self]
            for manager in self.device_managers:
                broadcasters += manager.all_broadcasters()
            
            for broadcaster in broadcasters:
                while True:
                    try:
                        broadcast = broadcaster.broadcast_messages.get(False)
                        broadcaster.broadcast_messages.task_done()

                        logger.debug("Got %s", broadcast)
                        if broadcast.destination is None:
                            self.current_state[broadcast.key] = broadcast

                        for receiver in broadcasters:
                            receiver.broadcast_received(broadcast)
                        
                    except queue.Empty:
                        # Nothing available, just move on...
                        break
                    
                    except Exception, e:
                        logger.debug("Exception: %s\n%s", e, traceback.format_exc())

            time.sleep(0.2)


subprocess.call("hciconfig hci0 up", shell=True)
subprocess.call("hciconfig hci1 up", shell=True)
scanner = Scanner()
managers = [
    UARTManager(),
    PIManager(),
    ThermostatManager(),
    BeanManager(),
    ControllerManager(),
    SocketManager(),
    StateManager(),
    WiFiManager(),
]
coordinator = Coordinator(managers)

logger.debug("Starting scan")
while True:
    try:
        devices = scanner.scan(2)
        for manager in managers:
            manager.found_devices(devices)
    except Exception, e:
        logger.debug("Exception on main loop: %s\n%s", e, traceback.format_exc())
        subprocess.call("hciconfig hci0 up", shell=True)
        subprocess.call("hciconfig hci1 up", shell=True)
        scanner = Scanner()
