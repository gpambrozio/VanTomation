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

        
    def set_coordinator(self, coordinator, identifier):
        self.coordinator = coordinator
        self.coordinator_identifier = identifier
        
        
    def found_devices(self, devices):
        # Check if everything is OK
        for addr in self.threads_by_addr.keys():   # .keys() creates a copy and avoids error due to removing key
            t = self.threads_by_addr[addr]
            if not t.is_alive():
                if self.coordinator is not None:
                    self.coordinator.device_disconnected(t, self.coordinator_identifier)
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
                        self.coordinator.device_connected(t, self.coordinator_identifier)
                except Exception, e:
                    logger.debug("Exception connecting to %s: %s", dev.addr, e)
                    # logger.debug(traceback.format_exc())


class NotificationDelegate(DefaultDelegate):
    def __init__(self):
        DefaultDelegate.__init__(self)
        self.last_data = None

    def handleNotification(self, cHandle, data):
        self.last_data = (cHandle, data)


class DeviceThread(object):
    def __init__(self, manager, dev, name, service_and_char_uuids):
        """ Constructor
        """
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
        self.received_commands = queue.Queue()
        
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

        
    def execute_command(self, full_command):
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
        self.received_data = queue.Queue()
        service_uuid = self.service_and_char_uuids[0][0]
        self.tx_characteristic = self.characteristics[service_uuid][0]
        self.rx_characteristic = self.characteristics[service_uuid][1]
        self.start_notifications(self.rx_characteristic)


    def received_data(self, cHandle, data):
        # Maybe use this for something..
        # self.received_data.put(data)
        pass

        
    def no_data_received(self):
        pass


    def write(self, data):
        """Write a string of data to the UART device."""
        self.add_command(lambda: self.tx_characteristic.write(data))


    def execute_command(self, full_command):
        command = full_command[1]
        if command not in "CRT":
            logger.debug("Unknown command: %s", command)
            return
        color = binascii.unhexlify(full_command[3:])
        command = full_command[1:3] + color

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
            read_data = self.received_data.get(timeout=timeout_sec)
            self.received_data.task_done()
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
            self.received_commands.put(data)


    def update_connected_devices(self, devices):
        self.add_command(lambda: self.devices_characteristic.write(devices))


    def execute_command(self, full_command):
        self.add_command(lambda: self.command_characteristic.write(full_command))
        
        
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
        self.temperature = 0
        self.humidity = 0


    def received_data(self, cHandle, data):
        if cHandle == self.temperature_characteristic.getHandle():
            self.temperature = float(struct.unpack('<h', data)[0])
            logger.debug('Temp: %.1f' % (self.temperature / 10))
            self.received_commands.put("CT%d" % self.temperature)
        elif cHandle == self.humidity_characteristic.getHandle():
            self.humidity = float(struct.unpack('<h', data)[0])
            logger.debug('Hum: %.1f %%' % (self.humidity / 10))
            self.received_commands.put("CH%d" % self.humidity)
        else:
            logger.debug("Unknown handle %d", cHandle)


    def execute_command(self, full_command):
        command = full_command[1]
        if command not in "SO":
            logger.debug("Unknown command: %s", command)
            return

        if command == "S":
            temp = int(full_command[2:])
            logger.debug("Setting temp to %d", temp)
            self.add_command(lambda: self.target_characteristic.write(struct.pack('<h', temp)))
        if command == "O":
            onoff = int(full_command[2:])
            logger.debug("Setting onoff to %d", onoff)
            self.add_command(lambda: self.onoff_characteristic.write('\x01' if onoff else '\x00'))


class PIManager(object):
    def __init__(self):
        self.addr = 'localhost'
        self.threads_by_addr = {self.addr: self}
        self.received_commands = queue.Queue()


    def set_coordinator(self, coordinator, identifier):
        self.coordinator = coordinator
        self.coordinator_identifier = identifier
        self.coordinator.device_connected(self, self.coordinator_identifier)

        
    def execute_command(self, full_command):
        logger.debug("Pi received command %s", full_command)
        command = full_command[1]
        if command not in "LU":
            logger.debug("Unknown command: %s", command)
            return
            
        port = 7 if command == "L" else 0
        subprocess.call("gpio mode %d out" % port, shell=True)
        subprocess.call("gpio write %d 1" % port, shell=True)
        time.sleep(0.3)
        subprocess.call("gpio write %d 0" % port, shell=True)
        time.sleep(0.2)
        subprocess.call("gpio write %d 1" % port, shell=True)
        time.sleep(0.3)
        subprocess.call("gpio write %d 0" % port, shell=True)


    def found_devices(self, devices):
        pass


class Coordinator(object):
    
    def __init__(self, controller_manager, device_managers):
        self.connected_devices = set()
        
        self.devices = {
            'C': 'Controllers',
            'L': 'fd:6e:55:f0:de:06',
            'P': 'localhost',
            'T': 'c7:be:4a:5b:80:4d'
        }
        
        self.devices_by_addr = {v: k for (k, v) in self.devices.iteritems()}
        
        self.controller_manager = controller_manager
        self.device_managers = device_managers
        for manager in device_managers:
            manager.set_coordinator(self, "D")

        controller_manager.set_coordinator(self, "C")
        
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True                            # Daemonize thread
        self.thread.start()                                  # Start the execution
        

    def device_connected(self, thread, coordinator_identifier):
        if coordinator_identifier == "D":
            self.connected_devices.add(thread.addr)

        self.update_connected_devices()


    def device_disconnected(self, thread, coordinator_identifier):
        if coordinator_identifier == "D":
            self.connected_devices.remove(thread.addr)
            self.update_connected_devices()


    def update_connected_devices(self):
        connected = "!" + ("".join(sorted([self.devices_by_addr[addr] for addr in self.connected_devices if addr in self.devices_by_addr])))
        for controller in self.controller_manager.threads_by_name.values():
            logger.debug("Updating devices: %s to %s", connected, controller.name)
            controller.update_connected_devices(connected)


    def run(self):
        """ Method that runs forever """

        while True:
            all_devices_by_addr = {}
            for manager in self.device_managers:
                all_devices_by_addr.update(manager.threads_by_addr)

            device_threads_by_name = self.controller_manager.threads_by_addr.values() + all_devices_by_addr.values()
            
            for device_threads in device_threads_by_name:
                try:
                    full_command = device_threads.received_commands.get(False)
                    device_threads.received_commands.task_done()
                    
                    logger.debug("Got command %s", full_command)
                    device_id = full_command[0]
                    if device_id == "C":
                        for controller in self.controller_manager.threads_by_addr.values():
                            controller.execute_command(full_command)
                        continue

                    device_addr = self.devices.get(device_id)
                    if device_addr is None:
                        logger.debug("Device %s unknown", device_id)
                        continue
                    device_thread = all_devices_by_addr.get(device_addr)
                    if device_thread is None:
                        logger.debug("Device %s (%s) not connected", device_id, device_addr)
                        logger.debug("connected: %s", all_devices_by_addr)
                        continue

                    device_thread.execute_command(full_command)
                        
                except Queue.Empty:
                    # Nothing available, just move on...
                    pass
                    
                except Exception, e:
                    logger.debug("Exception: %s\n%s", e, traceback.format_exc())

            time.sleep(0.2)


scanner = Scanner()
uart_manager = UARTManager()
pi_manager = PIManager()
thermostat_manager = ThermostatManager()
controller_manager = ControllerManager()
managers = [
    uart_manager,
    pi_manager,
    thermostat_manager,
]
coordinator = Coordinator(controller_manager, managers)

logger.debug("Starting scan")
while True:
    try:
        devices = scanner.scan(1)
        for manager in managers:
            manager.found_devices(devices)
        controller_manager.found_devices(devices)
    except Exception, e:
        logger.debug("Exception on main loop: %s\n%s", e, traceback.format_exc())
        scanner.clear()
