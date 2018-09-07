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
    ["Speed", "%d mph", 1],
    ["Heading", "%d", 1],
    ["Altitude", "%d ft", 3.281],
    ["Altitude", "%d m", 1.0],
]

title = tk.Label(root, text="Hello NonVanLifers!", font="Helvetica 30")
title.grid(row=0, columnspan=2)
spacer = tk.Label(root, text=" ", font="Helvetica 10")
spacer.grid(row=1, columnspan=2)

ui = [tk.Label(root, text="", font="Helvetica 24") for line in lines]
for (n, line) in enumerate(lines):
    title = tk.Label(root, text=line[0], font="Helvetica 24")
    title.grid(row=n+2, column=0, sticky=tk.W)
    ui[n].grid(row=n+2, column=1, sticky=tk.W)

def reload():
    read_state()
    for (n, line) in enumerate(lines):
        if line[0] in state:
            ui[n].config(text=line[1] % (line[2] * state[line[0]]["value"]))
    root.after(1000, reload)

reload()
root.mainloop()
