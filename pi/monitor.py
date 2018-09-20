#!/usr/bin/python

import Tkinter as tk
import json
import datetime
import time
import os
import logging
import traceback
import threading
import Queue as queue

import ephem
import pyowm
import requests

from PIL import ImageTk
from PIL import Image


FORMAT = '%(asctime)-15s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger()
logger.setLevel(logging.WARNING)

state = {}

OWM_API_KEY = os.getenv('OWM_API_KEY')
if OWM_API_KEY is None:
    logger.warning('OWM_API_KEY not set. Weather data won\'t be fetched')


sunset = None
sunrise = None
next_ss_calculation = 0
def sunrise_sunset(location):
    global next_ss_calculation, sunrise, sunset
    if time.time() >= next_ss_calculation:
        next_ss_calculation = time.time() + 60 * 60
        o = ephem.Observer()
        o.lat = "%f" % location[0]
        o.long = "%f" % location[1]
        s = ephem.Sun()
        s.compute()  
        sunrise = ephem.localtime(o.next_rising(s))
        sunset = ephem.localtime(o.next_setting(s))
    return u"\N{UPWARDS ARROW} %s\n\N{DOWNWARDS ARROW} %s" % (
        sunrise.strftime("%I:%M"),
        sunset.strftime("%I:%M")
    )


root = tk.Tk()
root.title("Hello NonVanLifers!")

lines = {
    "Temperature:Thermostat": [34, 2*60, lambda x: "i ?" if x is None else u"i %.1f \N{DEGREE SIGN}F" % x],
    "Temperature:AgnesOutside": [34, 2*60, lambda x: "o ?" if x is None else u"o %.1f \N{DEGREE SIGN}F" % x],
    "Humidity:Thermostat": [34, 2*60, lambda x: "? %%" if x is None else "%.1f%%" % x],
    "Speed:Socket": [60, 60, lambda x: "?" if x is None else "%d" % x],
    "Altitude:Socket": [34, 24*60*60, lambda x: "?" if x is None else "%d ft\n%d m" % (x * 3.281, x)],
    "Location:Socket": [16, 24*60*60, lambda x: "?" if x is None else sunrise_sunset(x)],
}

ui = {k: tk.Label(root, text=v[2](None), font="Helvetica %d" % v[0]) for (k, v) in lines.iteritems()}

ui["Speed:Socket"].grid(row=0, column=0, padx=2, pady=5, columnspan=2, sticky=tk.E)
tk.Label(root, text="m\np\nh", font="Helvetica 20").grid(row=0, column=2, padx=2, pady=5, columnspan=1, sticky=tk.W)

ui["Temperature:Thermostat"].grid(row=2, column=0, sticky=tk.E, padx=20, columnspan=3)
ui["Temperature:AgnesOutside"].grid(row=3, column=0, sticky=tk.E, padx=20, columnspan=3)
ui["Humidity:Thermostat"].grid(row=4, column=0, sticky=tk.E, padx=20, columnspan=3)

ui["Location:Socket"].grid(row=2, column=3, columnspan=3)
ui["Altitude:Socket"].grid(row=3, column=3, rowspan=2, padx=5, columnspan=3)


## Time
time_label = tk.Label(root, text="00:00 PM", font="Helvetica 50")
time_label.grid(row=1, column=0, columnspan=6)

def fill_time(state):
    time_label.config(text=datetime.datetime.now().strftime("%I:%M %p"))

## Heading
heading_canvas = tk.Canvas(root, width=100, height=100)

compass_image = ImageTk.PhotoImage(Image.open("./compass.png").resize((100, 100), Image.ANTIALIAS))
compass_object = heading_canvas.create_image(50, 50, image=compass_image)

compass_arrow = Image.open("./compass-arrow.png").resize((150, 150), Image.ANTIALIAS)
compass_arrow_image = ImageTk.PhotoImage(compass_arrow)
compass_arrow_object = heading_canvas.create_image(50, 50, image=compass_arrow_image)

heading_canvas.grid(row=0, column=3, padx=5, pady=20, columnspan=3)

def fill_heading(state):
    global compass_arrow_image, compass_arrow_object
    heading = state.get("Heading:Socket")
    if heading is not None:
        heading_canvas.delete(compass_arrow_object)
        compass_arrow_image = ImageTk.PhotoImage(compass_arrow.rotate(heading["value"]))
        compass_arrow_object = heading_canvas.create_image(50, 50, image=compass_arrow_image)

## Weather
weather_canvas = tk.Canvas(root, width=70, height=70)
weather_canvas.grid(row=5, column=0, columnspan=2)

weather_current_label = tk.Label(root, text="?", font="Helvetica 20")
weather_current_label.grid(row=5, column=2, columnspan=4)

weather_current_image = None
weather_current_object = None

class WeatherThread:
    def __init__(self, api_key, weather_data_queue):
        self.owm = pyowm.OWM(api_key)
        self.weather_data_queue = weather_data_queue
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True                            # Daemonize thread
        self.thread.start()                                  # Start the execution

    def download_weather_icon(self, icon_name):
        icon_file_name = "./owm_icons/%s.png" % icon_name
        if not os.path.exists(icon_file_name):
            icon = requests.get("http://openweathermap.org/img/w/%s.png" % icon_name)
            if icon.status_code == 200:
                f = file(icon_file_name, "w")
                f.write(icon.content)
                f.close()
            else:
                logger.error("Error getting http://openweathermap.org/img/w/%s.png %d", icon_name, icon.status_code)
                return None
        return icon_file_name

    def run(self):
        # Sleep a bit to make sure we get a state in the beginning
        time.sleep(2)
        while True:
            location = state.get("Location:Socket")
            if location is None:
                time.sleep(30 * 60)
            else:
                location = location["value"]
                try:
                    weather_data = {}
                    obs = self.owm.weather_at_coords(location[0], location[1])
                    weather = obs.get_weather()

                    weather_data['current'] = weather.get_detailed_status().capitalize()
                    weather_data['temperature'] = weather.get_temperature('fahrenheit')['temp']
                    weather_data['icon_file'] = self.download_weather_icon(weather.get_weather_icon_name())

                    # forecast = self.owm.three_hours_forecast_at_coords(location[0], location[1])

                    self.weather_data_queue.put(weather_data)
                    # No need to refetch for a while
                    time.sleep(15 * 60 * 60)

                except pyowm.exceptions.api_call_error.APICallTimeoutError as e:
                    logger.error("Exception: %s\n%s", e, traceback.format_exc())
                    # normal...
                    # Try again in 5 minues
                    time.sleep(5 * 60 * 60)

                except Exception as e:
                    logger.error("Exception: %s\n%s", e, traceback.format_exc())
                    # Try again in 5 minues
                    time.sleep(5 * 60 * 60)


weather_data_queue = queue.LifoQueue()
def fill_weather(state):
    global weather_current_image, weather_current_object, weather_data_queue

    try:
        weather_data = weather_data_queue.get_nowait()

        weather_current_label.config(text=u"%s\n%.0f \N{DEGREE SIGN}F" % (weather_data['current'], weather_data['temperature']))

        icon = Image.open(weather_data['icon_file'])
        if weather_current_object is not None:
            weather_canvas.delete(weather_current_object)
            weather_current_image = None
            weather_current_object = None

        if icon is not None:
            weather_current_image = ImageTk.PhotoImage(icon.resize((70, 70), Image.ANTIALIAS))
            weather_current_object = weather_canvas.create_image(35, 35, image=weather_current_image)

        # empty the queue
        while True:
            weather_data_queue.get_nowait()

    except queue.Empty:
        # normal...
        pass


weather_thread = WeatherThread(OWM_API_KEY, weather_data_queue) if OWM_API_KEY is not None else None


def read_state():
    try:
        state_file = open("/tmp/vantomation.state.json", "r")
        state = json.load(state_file)
        state_file.close()
        return state
    except Exception as e:
        print("Error: %s" % e)
        return {}


def reload():
    global state
    state = read_state()
    for (k, v) in lines.iteritems():
        if k in state:
            ts = state[k]["ts"]
            if (time.time() - ts > v[1]):
                ui[k].config(text=v[2](None))
            else:
                ui[k].config(text=v[2](state[k]["value"]))
    fill_time(state)
    fill_heading(state)
    fill_weather(state)
    root.after(1000, reload)


try:
    reload()
except Exception as e:
    print("Exception: %s" % e)

root.mainloop()
