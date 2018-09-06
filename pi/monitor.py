#!/usr/bin/python

import tkinter as tk
import json

# if you are still working under a Python 2 version, 
# comment out the previous line and uncomment the following line
# import Tkinter as tk

state_file = open("/tmp/vantomation.state.json", "r")

state = {}
def read_state():
    global state
    try:
        state_file.seek(0)
        state = json.load(state_file)
    except Exception as e:
        print("Error: %s" % e)
        pass

root = tk.Tk()
root.title("VanTomation")

lines = [
    ["Temperature", "%.1f F", 1.0],
    ["Humidity", "%.1f %%", 1.0],
    ["Heading", "%d", 1],
    ["Speed", "%d mph", 1],
    ["Altitude", "%d ft", 3.281],
    ["Altitude", "%d m", 1.0],
]

title = tk.Label(root, text="Hello NonVanLifers!", font="Helvetica 24")
title.pack()
spacer = tk.Label(root, text=" ", font="Helvetica 10")
spacer.pack()

ui = [tk.Label(root, text=line[0] + ": ?", font="Helvetica 18") for line in lines]
for element in ui:
    element.pack()

def reload():
    read_state()
    for (n, line) in enumerate(lines):
        if line[0] in state:
            ui[n].config(text=("%s: " + line[1]) % (line[0], line[2] * state[line[0]]["value"]))
    root.after(1000, reload)

reload()
root.mainloop()
