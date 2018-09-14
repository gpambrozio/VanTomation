#!/usr/bin/python

import Tkinter as tk
import json
import datetime
import time

from PIL import ImageTk
from PIL import Image

# if you are still working under a Python 2 version, 
# comment out the previous line and uncomment the following line

root = tk.Tk()
root.title("Hello NonVanLifers!")

canvas = tk.Canvas(root, width=100, height=100)

compass = Image.open("./compass.png").resize((100, 100), Image.ANTIALIAS)
compass_image = ImageTk.PhotoImage(compass)
compass_object = canvas.create_image(50, 50, image=compass_image)

compass_arrow = Image.open("./compass-arrow.png").resize((150, 150), Image.ANTIALIAS)
compass_arrow_image = ImageTk.PhotoImage(compass_arrow)
compass_arrow_object = canvas.create_image(50, 50, image=compass_arrow_image)

lines = {
    "Temperature:Thermostat": [34, lambda x: "b ?" if x is None else u"b %.1f \N{DEGREE SIGN}F" % x],
    "Temperature:AgnesInside": [34, lambda x: "f ?" if x is None else u"f %.1f \N{DEGREE SIGN}F" % x],
    "Temperature:AgnesOutside": [34, lambda x: "o ?" if x is None else u"o %.1f \N{DEGREE SIGN}F" % x],
    "Humidity:Thermostat": [34, lambda x: "? %%" if x is None else "%.1f%%" % x],
    "Speed:Socket": [60, lambda x: "?" if x is None else "%d" % x],
    "Altitude:Socket": [34, lambda x: "?" if x is None else "%d ft\n%d m" % (x * 3.281, x)],
}

ui = {k: tk.Label(root, text=v[1](0), font="Helvetica %d" % v[0]) for (k, v) in lines.iteritems()}

ui["Speed:Socket"].grid(row=0, column=0, padx=2, pady=5, columnspan=2, sticky=tk.E)
tk.Label(root, text="m\np\nh", font="Helvetica 20").grid(row=0, column=2, padx=2, pady=5, columnspan=1, sticky=tk.W)
canvas.grid(row=0, column=3, padx=5, pady=20, columnspan=3)

time_label = tk.Label(root, text="00:00 PM", font="Helvetica 50")
time_label.grid(row=1, column=0, columnspan=6)

ui["Temperature:Thermostat"].grid(row=2, column=0, sticky=tk.E, padx=20, columnspan=3)
ui["Temperature:AgnesInside"].grid(row=3, column=0, sticky=tk.E, padx=20, columnspan=3)
ui["Temperature:AgnesOutside"].grid(row=4, column=0, sticky=tk.E, padx=20, columnspan=3)
ui["Humidity:Thermostat"].grid(row=2, column=3, sticky=tk.W, padx=20, columnspan=3)
ui["Altitude:Socket"].grid(row=3, column=3, rowspan=2, padx=5, columnspan=3)

state = {}
def read_state():
    global state
    try:
        state_file = open("/tmp/vantomation.state.json", "r")
        state = json.load(state_file)
        state_file.close()
    except Exception as e:
        print("Error: %s" % e)
        pass

def reload():
    global compass_arrow_image, compass_arrow_object
    time_label.config(text=datetime.datetime.now().strftime("%I:%M %p"))
    read_state()
    for (k, v) in lines.iteritems():
        if k in state:
            ts = state[k]["ts"]
            if (time.time() - ts > 2*60000):
                ui[k].config(text=v[1](None))
            else:
                ui[k].config(text=v[1](state[k]["value"]))
    if "Heading:Socket" in state:
        heading = state["Heading:Socket"]["value"]
        canvas.delete(compass_arrow_object)
        compass_arrow_image = ImageTk.PhotoImage(compass_arrow.rotate(heading))
        compass_arrow_object = canvas.create_image(50, 50, image=compass_arrow_image)
    root.after(1000, reload)

try:
    reload()
except Exception as e:
    print("Exception: %s" % e)
    pass

root.mainloop()
