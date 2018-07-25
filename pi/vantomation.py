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

def reverse_uuid(service_uuid):
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
                print("Device %s thread died... Removing" % addr)

        for dev in devices:
            scan_data = dev.getScanData()
            services = set([s[2] for s in scan_data if s[0] == 7])

            if self.required_services <= services and dev.addr not in self.threads_by_addr:
                try:
                    print("Found device %s type %s" % (dev.addr, type(self)))
                    t = self.thread_class(self, dev, self.service_and_char_uuids)
                    print("Connected to %s (%s)" % (dev.addr, t.name))
                    self.threads_by_addr[dev.addr] = t
                    self.threads_by_name[t.name] = t
                    if self.coordinator is not None:
                        self.coordinator.device_connected(t, self.coordinator_identifier)
                except Exception, e:
                    print("Exception connecting to %s: %s" % (dev.addr, e))
                    print(traceback.format_exc())


class NotificationDelegate(DefaultDelegate):
    def __init__(self):
        DefaultDelegate.__init__(self)
        self.last_data = None

    def handleNotification(self, cHandle, data):
        self.last_data = (cHandle, data)


class DeviceThread(object):
    def __init__(self, manager, dev, service_and_char_uuids):
        """ Constructor
        """
        self.manager = manager
        self.dev = dev
        self.service_and_char_uuids = service_and_char_uuids
        
        self.name = dev.getValueText(9)

        self.delegate = NotificationDelegate()
        self.peripheral = btle.Peripheral()
        self.peripheral.setDelegate(self.delegate)
        self.peripheral.connect(self.dev)

        # print("services %s" % [s.uuid.getCommonName() for s in self.peripheral.getServices()])
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
                    print("Received %s from %s" % (self.delegate.last_data, self.name))
                    self.received_data(self.delegate.last_data[0], self.delegate.last_data[1])
                else:
                    self.no_data_received()

            except BTLEException, e:
                print("BTLEException: %s\n%s" % (e, traceback.format_exc()))
                if e.code != BTLEException.DISCONNECTED:
                    self.peripheral.disconnect()
                break

            except Exception, e:
                print("Exception: %s\n%s" % (e, traceback.format_exc()))
                
            try:
                command = self.commands.get(False)
                command()
                self.commands.task_done()
            except queue.Empty:
                pass
            except Exception, e:
                print("Exception: %s\n%s" % (e, traceback.format_exc()))


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
        self.queue = queue.Queue()
        service_uuid = self.service_and_char_uuids[0][0]
        self.tx_characteristic = self.characteristics[service_uuid][0]
        self.rx_characteristic = self.characteristics[service_uuid][1]
        self.start_notifications(self.rx_characteristic)


    def received_data(self, cHandle, data):
        self.queue.put(data)

        
    def no_data_received(self):
        pass


    def write(self, data):
        """Write a string of data to the UART device."""
        self.add_command(lambda: self.tx_characteristic.write(data))


    def send_command(self, command):
        print("Sending command %s to %s" % (binascii.hexlify(command), self.name))
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
            read_data = self.queue.get(timeout=timeout_sec)
            self.queue.task_done()
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
        self.queue = queue.Queue()


    def received_data(self, cHandle, data):
        if cHandle == self.command_characteristic.getHandle():
            self.queue.put(data)


    def update_connected_devices(self, devices):
        self.add_command(lambda: self.devices_characteristic.write(devices))
        

class Coordinator(object):
    
    def __init__(self, controller_manager, device_managers):
        self.controller_manager = controller_manager
        self.device_managers = device_managers
        for manager in device_managers:
            manager.set_coordinator(self, "D")

        controller_manager.set_coordinator(self, "C")
        
        self.devices = {
            'L': 'AgnesLights',
            'I': 'AgnesInsides',
        }
        
        self.devices_by_name = {v: k for (k, v) in self.devices.iteritems()}
        
        self.connected_devices = set()
        
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True                            # Daemonize thread
        self.thread.start()                                  # Start the execution
        

    def device_connected(self, thread, coordinator_identifier):
        if coordinator_identifier == "D":
            self.connected_devices.add(thread.name)

        self.update_connected_devices()


    def device_disconnected(self, thread, coordinator_identifier):
        if coordinator_identifier == "D":
            self.connected_devices.remove(thread.name)
            self.update_connected_devices()


    def update_connected_devices(self):
        connected = "!" + ("".join(sorted([self.devices_by_name[name] for name in self.connected_devices if name in self.devices_by_name])))
        for controller in self.controller_manager.threads_by_name.values():
            print("Updating devices: %s to %s" % (connected, controller.name))
            controller.update_connected_devices(connected)


    def run(self):
        """ Method that runs forever """

        while True:
            for controller in self.controller_manager.threads_by_name.values():
                try:
                    full_command = controller.queue.get(False)
                    controller.queue.task_done()
                    
                    print("Got command %s" % full_command)
                    all_devices_by_name = {}
                    for manager in self.device_managers:
                        all_devices_by_name.update(manager.threads_by_name)
                    command = full_command[0]
                    device_id = full_command[1]
                    device_name = self.devices.get(device_id)
                    if device_name is None:
                        print("Device %s unknown" % device_id)
                        continue
                    device_thread = all_devices_by_name.get(device_name)
                    if device_thread is None:
                        print("Device %s (%s) not connected" % (device_id, device_name))
                        continue
                    
                    if command == 'C':
                        strip = full_command[2]
                        color = binascii.unhexlify(full_command[3:])
                        device_thread.send_command("C" + strip + color)
                        
                except Queue.Empty:
                    # Nothing available, just move on...
                    pass
                    
                except Exception, e:
                    print("Exception: %s\n%s" % (e, traceback.format_exc()))

            time.sleep(0.2)


scanner = Scanner()
uart_manager = UARTManager()
controller_manager = ControllerManager()
coordinator = Coordinator(controller_manager, [uart_manager])
print("Starting scan")
while True:
    devices = scanner.scan(1)
    uart_manager.found_devices(devices)
    controller_manager.found_devices(devices)
