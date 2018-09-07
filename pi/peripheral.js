var util = require('util');
var bleno = require('bleno');
var net = require('net');
const fs = require('fs');

// Not perfect but works. Came from https://stackoverflow.com/questions/18814221/adding-timestamps-to-all-console-messages
var log = console.log;
console.log = function(){
  log.apply(console, [(new Date()).toTimeString()].concat(arguments));
};

var client = null;
fs.watch('/tmp', (eventType, filename) => {
  if (client == null && filename == 'vantomation.socket' && eventType == 'rename') {
    console.log('socket created');
    client = startClient();
  }
});
if (fs.existsSync('/tmp/vantomation.socket')) {
  client = startClient();
}

function startClient() {
  const c = net.createConnection({ path: '/tmp/vantomation.socket' }, () => {
    // 'connect' listener
    console.log('connected to server!');
  });
  c.on('data', (data) => {
    console.log(data.toString());
    c.end();
  });
  c.on('end', () => {
    console.log('disconnected from server');
    client = null;
  });
  return c;
}

function relay(msg) {
  if (client != null) {
    client.write(msg+'\n');
  }
}

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

  console.log('onWriteRequest: ' + this._value.toString());
  relay(this._value.toString());

  callback(this.RESULT_SUCCESS);
};

console.log('bleno - echo');

bleno.on('stateChange', function(state) {
  console.log('on -> stateChange: ' + state);

  if (state === 'poweredOn') {
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

var interval = null;

bleno.on('accept', function(clientAddress) {
  console.log("Accepted connection from: " + clientAddress);
  interval = setInterval(function() {
    bleno.updateRssi();
  }, 5000);
});

bleno.on('disconnect', function(clientAddress) {
  clearInterval(interval);
  console.log("Disconnected from: " + clientAddress);
});

bleno.on('rssiUpdate', function(rssi) {
    console.log("RSSI: " + rssi);
});
