#!/bin/bash

dnf copr enable avengemedia/dms
dnf install niri dms
systemctl enable dms
