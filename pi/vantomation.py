#!/usr/bin/python

from bluepy.btle import Scanner, DefaultDelegate, BTLEException
from bluepy import btle
import threading
import queue
import Queue
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
                except Exception, e:
                    logger.debug("Exception connecting to %s: %s", dev.addr, e)
                    # logger.debug(traceback.format_exc())


class NotificationDelegate(DefaultDelegate):
    def __init__(self):
        DefaultDelegate.__init__(self)
        self.last_data = None


    def handleNotification(self, cHandle, data):
        self.last_data = (cHandle, data)


class BroadcastMessage(object):
    def __init__(self, destination, prop, value):
        self.destination = destination
        self.prop = prop
        self.value = value
        
        
    def __str__(self):
        return "Broadcast to %s, %s = %s" % (self.destination, self.prop, self.value)

        

class SenderReceiver(object):
    def __init__(self):
        self.broadcast_messages = queue.Queue()
        

    def found_devices(self, devices):
        pass


    def broadcast_received(self, broadcast):
        pass


    def add_broadcast(self, destination, prop, value):
        self.broadcast_messages.put(BroadcastMessage(destination, prop, value))


    def all_broadcasters(self):
        return [self]


    def set_coordinator(self, coordinator):
        pass



class DeviceThread(SenderReceiver):
    def __init__(self, manager, dev, name, service_and_char_uuids):
        """ Constructor
        """
        SenderReceiver.__init__(self)

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


    def broadcast_received(self, broadcast):
        if broadcast.destination is not None and broadcast.destination.startswith("Light:") and broadcast.prop == "Mode":
            strip = broadcast.destination[-1]
        
            mode = broadcast.value[0]
            if mode not in "CRT":
                logger.debug("Unknown mode: %s", mode)
                return

            color = binascii.unhexlify(broadcast.value[1:])
            command = mode + strip + color

            logger.debug("Sending command %s to %s", binascii.hexlify(command), self.name)
            full_command = "!" + chr(len(command) + 3) + command
            checksum = 0
            for c in full_command:
                checksum += ord(c)
            checksum = (checksum & 0xFF) ^ 0xFF
            full_command += chr(checksum)
            self.write(full_command)


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
                self.add_broadcast("Thermostat", "Target", data[2:])
            else:
                logger.info("Unknown destination: %s" % data)


    def broadcast_received(self, broadcast):
        if broadcast.destination == None and broadcast.prop == "Devices":
            self.add_command(lambda: self.devices_characteristic.write("CD" + broadcast.value))
        elif broadcast.destination == None and broadcast.prop == "Temperature":
            self.add_command(lambda: self.devices_characteristic.write("CT%.0f" % (broadcast.value * 10)))
        elif broadcast.destination == None and broadcast.prop == "Humidity":
            self.add_command(lambda: self.devices_characteristic.write("CH%.0f" % (broadcast.value * 10)))
        elif broadcast.destination == None and broadcast.prop == "ThermostatState":
            self.add_command(lambda: self.devices_characteristic.write("Ct" + broadcast.value))

        
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
        self.temperature_characteristic = self.characteristics[service_uuid][0]
        self.humidity_characteristic = self.characteristics[service_uuid][1]
        self.onoff_characteristic = self.characteristics[service_uuid][2]
        self.target_characteristic = self.characteristics[service_uuid][3]
        self.start_notifications(self.temperature_characteristic)
        self.start_notifications(self.humidity_characteristic)
        self.start_notifications(self.onoff_characteristic)
        self.start_notifications(self.target_characteristic)
        self.temperature = 0
        self.humidity = 0
        self.onoff = 0
        self.target = 0


    def received_data(self, cHandle, data):
        if cHandle == self.temperature_characteristic.getHandle():
            self.temperature = float(struct.unpack('<h', data)[0]) / 10
            self.add_broadcast(None, "Temperature", self.temperature)
        elif cHandle == self.humidity_characteristic.getHandle():
            self.humidity = float(struct.unpack('<h', data)[0]) / 10
            self.add_broadcast(None, "Humidity", self.humidity)
        elif cHandle == self.onoff_characteristic.getHandle():
            self.onoff = struct.unpack('B', data)[0]
            self.add_broadcast(None, "ThermostatState", "%01d%d" % (self.onoff, self.target))
        elif cHandle == self.target_characteristic.getHandle():
            self.target = float(struct.unpack('<h', data)[0])
            self.add_broadcast(None, "ThermostatState", "%01d%d" % (self.onoff, self.target))
        else:
            logger.debug("Unknown handle %d", cHandle)


    def broadcast_received(self, broadcast):
        if broadcast.destination == "Thermostat" and broadcast.prop == "Target":
            onoff = int(broadcast.value[0])
            temp = int(broadcast.value[1:], 16)
            logger.debug("Setting temp to %d, onoff to %d", temp, onoff)
            self.add_command(lambda: self.target_characteristic.write(struct.pack('<h', temp)))
            self.add_command(lambda: self.onoff_characteristic.write('\x01' if onoff else '\x00'))


class PIManager(SenderReceiver):
    def __init__(self):
        SenderReceiver.__init__(self)
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
        SenderReceiver.__init__(self)
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
        SenderReceiver.__init__(self)
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
        state = {k: {'ts': v[0], 'value': v[1].value } for (k, v) in self.current_state.iteritems()}
        state_file = open("/tmp/vantomation.state.json", "w+")
        state_file.write(json.dumps(state))
        state_file.close()



class Coordinator(SenderReceiver):

    def __init__(self, device_managers):
        SenderReceiver.__init__(self)
        self.connected_devices = set()

        self.devices = {
            'L': 'fd:6e:55:f0:de:06',
            'T': 'eb:cc:ee:35:55:c0'
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
                            self.current_state[broadcast.prop] = (time.time(), broadcast)

                        for receiver in broadcasters:
                            receiver.broadcast_received(broadcast)
                        
                    except Queue.Empty:
                        # Nothing available, just move on...
                        break
                    
                    except Exception, e:
                        logger.debug("Exception: %s\n%s", e, traceback.format_exc())

            time.sleep(0.2)


subprocess.call("hciconfig hci0 up", shell=True)
scanner = Scanner()
managers = [
    UARTManager(),
    PIManager(),
    ThermostatManager(),
    ControllerManager(),
    SocketManager(),
    StateManager(),
]
coordinator = Coordinator(managers)

logger.debug("Starting scan")
while True:
    try:
        devices = scanner.scan(1)
        for manager in managers:
            manager.found_devices(devices)
    except Exception, e:
        logger.debug("Exception on main loop: %s\n%s", e, traceback.format_exc())
        scanner.clear()
