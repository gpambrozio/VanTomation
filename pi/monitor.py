#!/usr/bin/python

import Tkinter as tk
import json
import datetime
import time
import os
import logging
import traceback

import ephem
import pyowm
import requests

from PIL import ImageTk
from PIL import Image


FORMAT = '%(asctime)-15s %(message)s'
logging.basicConfig(format=FORMAT)
logger = logging.getLogger()
logger.setLevel(logging.WARNING)

OWM_API_KEY = os.getenv('OWM_API_KEY')
if OWM_API_KEY is None:
    logger.warning('OWM_API_KEY not set. Weather data won\'t be fetched')
    owm = None
else:
    owm = pyowm.OWM(OWM_API_KEY)


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


def weather_icon(icon_name):
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
    return Image.open(icon_file_name)


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
weather_current_label = tk.Label(root, text="?", font="Helvetica 20")
weather_current_label.grid(row=5, column=1, columnspan=3)
weather_temp_label = tk.Label(root, text="?", font="Helvetica 20")
weather_temp_label.grid(row=5, column=4, columnspan=2)

weather_canvas = tk.Canvas(root, width=30, height=30)
weather_canvas.grid(row=5, column=0, columnspan=1)

weather_current_image = None
weather_current_object = None

def fill_weather(state):
    global weather_current_image, weather_current_object
    if owm is None:
        return

    location = state.get("Location:Socket")
    if location is not None:
        location = location["value"]
        try:
            obs = owm.weather_at_coords(location[0], location[1])
            weather = obs.get_weather()
            weather_current_label.config(text=weather.get_detailed_status().capitalize())
            temp = weather.get_temperature('fahrenheit')
            weather_temp_label.config(text=u"%.0f \N{DEGREE SIGN}F" % temp['temp'])

            icon_name = weather.get_weather_icon_name()
            icon = weather_icon(icon_name)
            if weather_current_object is not None:
                weather_canvas.delete(weather_current_object)
                weather_current_image = None
                weather_current_object = None

            if icon is not None:
                weather_current_image = ImageTk.PhotoImage(icon.resize((30, 30), Image.ANTIALIAS))
                weather_current_object = weather_canvas.create_image(15, 15, image=weather_current_image)

#            forecast = owm.three_hours_forecast_at_coords(location[0], location[1])

        except pyowm.exceptions.api_call_error.APICallTimeoutError:
            # normal...
            pass

        except Exception as e:
            logger.error("Exception: %s\n%s", e, traceback.format_exc())


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
