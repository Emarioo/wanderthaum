#/usr/bin/env python3

import os

shaderdir = os.path.dirname(__file__)

if os.path.exists("vert.spv"):
    os.remove("vert.spv")
if os.path.exists("frag.spv"):
    os.remove("frag.spv")

os.system(f"glslc {shaderdir}/base.vert -o vert.spv")
os.system(f"glslc {shaderdir}/base.frag -o frag.spv")
