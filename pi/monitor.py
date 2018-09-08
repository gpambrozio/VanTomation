#!/usr/bin/python

import Tkinter as tk
import json

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
    "Temperature": [34, lambda x: "%.1f F" % x],
    "Humidity": [34, lambda x: "%.1f%%" % x],
    "Speed": [60, lambda x: "%d mph" % x],
    "Heading": [34, lambda x: "%d" % x],
    "Altitude": [34, lambda x: "%d ft\n%d m" % (x * 3.281, x)],
}

ui = {k: tk.Label(root, text=v[1](0), font="Helvetica %d" % v[0]) for (k, v) in lines.iteritems()}

ui["Temperature"].grid(row=0, column=0, sticky=tk.W, padx=5)

ui["Humidity"].grid(row=1, column=0, sticky=tk.W, padx=5)

ui["Speed"].grid(row=0, column=1, rowspan=2, padx=15, pady=5)
canvas.grid(row=0, column=2, rowspan=2, padx=5, pady=5)
ui["Altitude"].grid(row=0, column=3, rowspan=2, padx=5, pady=5)

state_file = None
state = {}
def read_state():
    global state
    try:
        state_file.seek(0)
        state = json.load(state_file)
    except Exception as e:
        print("Error: %s" % e)
        pass

def reload():
    global compass_arrow_image, compass_arrow_object
    read_state()
    for (k, v) in lines.iteritems():
        if k in state:
            ui[k].config(text=v[1](state[k]["value"]))
    if "Heading" in state:
        heading = state["Heading"]["value"]
        canvas.delete(compass_arrow_object)
        compass_arrow_image = ImageTk.PhotoImage(compass_arrow.rotate(-heading))
        compass_arrow_object = canvas.create_image(50, 50, image=compass_arrow_image)
    root.after(1000, reload)

try:
    state_file = open("/tmp/vantomation.state.json", "r")
    reload()
except:
    pass

root.mainloop()
