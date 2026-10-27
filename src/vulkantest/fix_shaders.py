#/usr/bin/env python3

import os
import time

shaderdir = os.path.dirname(__file__)

os.system(f"glslc {shaderdir}/base.vert -o vert.spv")
os.system(f"glslc {shaderdir}/base.frag -o frag.spv")
