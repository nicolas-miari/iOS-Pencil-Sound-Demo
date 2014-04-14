iOS-Pencil-Sound-Demo
=====================

This demo project uses Core Audio to simulate the sound of a pencil running on paper, 
driven by a drag on the multitouch screen.

How it works
------------

The Core Audio render callback provides a white noise signal (random samples using the C random() 
function), to which a bandpass filter is applied. The bandwidth parameter is fixed, but the center 
frequency parameter and the overall gain are proportional to the speed of touch drag. So when the 
user drags his finger faster, the app produces a louder, higher pitched sound, more or less like
a pencil against a sheet of paper.
