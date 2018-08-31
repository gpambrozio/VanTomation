var util = require('util');
var bleno = require('bleno');

var beacon_uuid = 'A495DEADC5B14B44B5121370F02D74DE';
var major = 0; // 0x0000 - 0xffff
var minor = 0; // 0x0000 - 0xffff
var measuredPower = -59; // -128 - 127

var EchoCharacteristic = function() {
  EchoCharacteristic.super_.call(this, {
    uuid: 'ec0e',
    properties: ['write', 'notify', 'read'],
    value: null
  });

  this._value = new Buffer('');
};

util.inherits(EchoCharacteristic, bleno.Characteristic);

EchoCharacteristic.prototype.onWriteRequest = function(data, offset, withoutResponse, callback) {
  this._value = data;

  console.log('EchoCharacteristic - onWriteRequest: value = ' + this._value.toString());

  callback(this.RESULT_SUCCESS);
};

console.log('bleno - echo');

bleno.on('stateChange', function(state) {
  console.log('on -> stateChange: ' + state);

  if (state === 'poweredOn') {
    // bleno.startAdvertisingIBeacon(beacon_uuid, major, minor, measuredPower, (err) => {
    //   console.log('Error starting beacon: ' + err);
    // });
    bleno.startAdvertising('echo', ['ec00']);
  } else {
    bleno.stopAdvertising();
  }
});

bleno.on('advertisingStart', function(error) {
  console.log('on -> advertisingStart: ' + (error ? 'error ' + error : 'success'));

  if (!error) {
    bleno.setServices([
      new bleno.PrimaryService({
        uuid: 'ec00',
        characteristics: [
          new EchoCharacteristic()
        ]
      })
    ]);
  }
});

bleno.on('advertisingStartError', (err) => {
  console.log(err);
});

bleno.on('advertisingStop', () => {
  console.log("Advertising Stopped");
});

bleno.on('servicesSet', (err) => {
  console.log("Set Services");
});

bleno.on('servicesSetError', (err) => {
  console.log(err);
});

bleno.on('accept', function(clientAddress) {
  console.log("Accepted connection from: " + clientAddress);
});

bleno.on('disconnect', function(clientAddress) {
  console.log("Disconnected from: " + clientAddress);
});
