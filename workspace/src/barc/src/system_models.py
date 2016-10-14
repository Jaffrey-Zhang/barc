#!/usr/bin/env python

# ---------------------------------------------------------------------------
# Licensing Information: You are free to use or extend these projects for 
# education or reserach purposes provided that (1) you retain this notice
# and (2) you provide clear attribution to UC Berkeley, including a link 
# to http://barc-project.com
#
# Attibution Information: The barc project ROS code-base was developed
# at UC Berkeley in the Model Predictive Control (MPC) lab by Jon Gonzales
# (jon.gonzales@berkeley.edu). The cloud services integation with ROS was developed
# by Kiet Lam  (kiet.lam@berkeley.edu). The web-server app Dator was 
# based on an open source project by Bruce Wootton
# ---------------------------------------------------------------------------

from numpy import sin, cos, tan, arctan, array, dot
from numpy import sign, argmin, sqrt
import rospy

def f_KinBkMdl(z,u,vhMdl, dt, est_mode):
    """
    process model
    input: state z at time k, z[k] := [x[k], y[k], psi[k], v[k]]
    output: state at next time step z[k+1]
    """
    #c = array([0.5431, 1.2767, 2.1516, -2.4169])

    # get states / inputs
    x       = z[0]
    y       = z[1]
    psi     = z[2]
    v       = z[3]

    d_f     = u[0]
    a       = u[1]

    # extract parameters
    (L_a, L_b)             = vhMdl

    # compute slip angle
    bta         = arctan( L_a / (L_a + L_b) * tan(d_f) )

    # compute next state
    x_next      = x + dt*( v*cos(psi + bta) )
    y_next      = y + dt*( v*sin(psi + bta) )
    psi_next    = psi + dt*v/L_b*sin(bta)
    v_next      = v + dt*(a - 0.63*sign(v)*v**2)

    return array([x_next, y_next, psi_next, v_next])

def f_KinBkMdl_psi_drift(z,u,vhMdl, dt, est_mode):
    """
    process model
    input: state z at time k, z[k] := [x[k], y[k], psi[k], v[k]]
    output: state at next time step z[k+1]
    """
    #c = array([0.5431, 1.2767, 2.1516, -2.4169])

    # get states / inputs
    x       = z[0]
    y       = z[1]
    psi     = z[2]
    v       = z[3]
    psi_drift = z[4]

    d_f     = u[0]
    a       = u[1]

    # extract parameters
    (L_a, L_b)             = vhMdl

    # compute slip angle
    bta         = arctan( L_a / (L_a + L_b) * tan(d_f) )

    # compute next state
    x_next      = x + dt*( v*cos(psi + bta) )
    y_next      = y + dt*( v*sin(psi + bta) )
    psi_next    = psi + dt*v/L_b*sin(bta)
    v_next      = v + dt*(a - 0.63*sign(v)*v**2)
    psi_drift_next = psi_drift

    return array([x_next, y_next, psi_next, v_next, psi_drift_next])


def f_KinBkMdl_predictive(z,u,vhMdl, dt, est_mode):
    """
    process model
    input: state z at time k, z[k] := [x[k], y[k], psi[k], v[k]]
    output: state at next time step z[k+1]
    """
    #c = array([0.5431, 1.2767, 2.1516, -2.4169])

    # get states / inputs
    x       = z[0]
    y       = z[1]
    psi     = z[2]
    v       = z[3]

    x_pred  = z[4]
    y_pred  = z[5]
    psi_pred= z[6]
    v_pred  = z[7]

    d_f     = u[0]
    a       = u[1]

    # extract parameters
    (L_a, L_b)             = vhMdl

    # compute slip angle
    bta         = arctan( L_a / (L_a + L_b) * tan(d_f) )

    dt_pred = 0.0
    # compute next state
    x_next      = x + dt*( v*cos(psi + bta) )
    y_next      = y + dt*( v*sin(psi + bta) )
    psi_next    = psi + dt*v/L_b*sin(bta)
    v_next      = v + dt*(a - 0.63*sign(v)*v**2)

    x_next_pred      = x_next   + dt_pred*( v*cos(psi + bta) )
    y_next_pred      = y_next   + dt_pred*( v*sin(psi + bta) ) 
    psi_next_pred    = psi_next + dt_pred*v/L_b*sin(bta)
    v_next_pred      = v_next   + dt_pred*(a - 0.63*sign(v)*v**2)

    return array([x_next, y_next, psi_next, v_next, x_next_pred, y_next_pred, psi_next_pred, v_next_pred])

def h_KinBkMdl(x, u, vhMdl, dt, est_mode):
    """
    measurement model
    """
    if est_mode==1:                     # GPS, IMU, Enc
        C = array([[1, 0, 0, 0],
                   [0, 1, 0, 0],
                   [0, 0, 1, 0],
                   [0, 0, 0, 1]])
    elif est_mode==2:                     # IMU, Enc
        C = array([[0, 0, 1, 0],
                   [0, 0, 0, 1]])
    elif est_mode==3:                     # GPS
        C = array([[1, 0, 0, 0],
                   [0, 1, 0, 0]])
    elif est_mode==4:                     # GPS, Enc
        C = array([[1, 0, 0, 0],
                   [0, 1, 0, 0],
                   [0, 0, 0, 1]])
    else:
        print("Wrong est_mode")
    return dot(C, x)

def h_KinBkMdl_psi_drift(x, u, vhMdl, dt, est_mode):
    """
    measurement model
    """
    if est_mode==1:                     # GPS, IMU, Enc
        C = array([[1, 0, 0, 0, 0],
                   [0, 1, 0, 0, 0],
                   [0, 0, 1, 0, 1],
                   [0, 0, 0, 1, 0]])
    elif est_mode==2:                     # IMU, Enc
        C = array([[0, 0, 1, 0, 1],
                   [0, 0, 0, 1, 0]])
    elif est_mode==3:                     # GPS
        C = array([[1, 0, 0, 0, 0],
                   [0, 1, 0, 0, 0]])
    elif est_mode==4:                     # GPS, Enc
        C = array([[1, 0, 0, 0, 0],
                   [0, 1, 0, 0, 0],
                   [0, 0, 0, 1, 0]])
    else:
        print("Wrong est_mode")
    return dot(C, x)

def h_KinBkMdl_predictive(x):
    """
    measurement model
    """
    # For GPS, IMU and encoders:
    # C = array([[1, 0, 0, 0],
    #            [0, 1, 0, 0],
    #            [0, 0, 1, 0],
    #            [0, 0, 0, 1]])
    # For GPS only:
    C = array([[1, 0, 0, 0, 0, 0, 0, 0],
               [0, 1, 0, 0, 0, 0, 0, 0],
               [0, 0, 1, 0, 0, 0, 0, 0]])
    return dot(C, x)
