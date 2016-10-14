#!/usr/bin/env julia

#=
 Licensing Information: You are free to use or extend these projects for 
 education or reserach purposes provided that (1) you retain this notice
 and (2) you provide clear attribution to UC Berkeley, including a link 
 to http://barc-project.com

 Attibution Information: The barc project ROS code-base was developed
 at UC Berkeley in the Model Predictive Control (MPC) lab by Jon Gonzales
 (jon.gonzales@berkeley.edu). The cloud services integation with ROS was developed
 by Kiet Lam  (kiet.lam@berkeley.edu). The web-server app Dator was 
 based on an open source project by Bruce Wootton
=# 

using RobotOS
@rosimport barc.msg: ECU, pos_info, Encoder, Ultrasound, Z_KinBkMdl, Logging, Z_DynBkMdl
@rosimport data_service.msg: TimeData
@rosimport geometry_msgs.msg: Vector3
@rosimport sensor_msgs.msg: Imu
@rosimport std_msgs.msg: Float32
rostypegen()
using barc.msg
using data_service.msg
using geometry_msgs.msg
using sensor_msgs.msg
using std_msgs.msg
using JLD

include("LMPC_lib/classes.jl")
include("LMPC_lib/simModel.jl")

u_current = zeros(Float64,2)      # msg ECU is Float32 !

t = 0

# This type contains measurement data (time, values and a counter)
type Measurements{T}
    i::Int64          # measurement counter
    t::Array{Float64}       # time data
    z::Array{T}       # measurement values
end

# This function cleans the zeros from the type above once the simulation is finished
function clean_up(m::Measurements)
    m.t = m.t[1:m.i-1]
    m.z = m.z[1:m.i-1,:]
end

buffersize = 60000
gps_meas = Measurements{Float64}(0,zeros(buffersize),zeros(buffersize,2))
imu_meas = Measurements{Float64}(0,zeros(buffersize),zeros(buffersize,2))
cmd_log  = Measurements{Float64}(0,zeros(buffersize),zeros(buffersize,2))
z_real   = Measurements{Float64}(0,zeros(buffersize),zeros(buffersize,8))
slip_a   = Measurements{Float64}(0,zeros(buffersize),zeros(buffersize,2))

z_real.t[1]   = time()
slip_a.t[1]   = time()
imu_meas.t[1] = time()
cmd_log.t[1]  = time()

function ECU_callback(msg::ECU)
    global u_current
    u_current = convert(Array{Float64,1},[msg.motor, msg.servo])
    cmd_log.i += 1
    cmd_log.t[cmd_log.i] = time()
    cmd_log.z[cmd_log.i,:] = u_current
end

function main() 
    # initiate node, set up publisher / subscriber topics
    init_node("barc_sim")
    pub_enc = Publisher("encoder", Encoder, queue_size=1)
    pub_gps = Publisher("indoor_gps", Vector3, queue_size=1)
    pub_imu = Publisher("imu/data", Imu, queue_size=1)
    pub_vel = Publisher("vel_est", Float32Msg, queue_size=1)

    s1  = Subscriber("ecu", ECU, ECU_callback, queue_size=1)

    z_current = zeros(60000,8)
    z_current[1,:] = [0.1 0.0 0.0 0.0 0.0 0.0 0.0 0.0]
    slip_ang = zeros(60000,2)

    dt = 0.01
    loop_rate = Rate(1/dt)

    i = 2

    dist_traveled = 0
    last_updated  = 0

    r_tire      = 0.036                  # radius from tire center to perimeter along magnets [m]
    quarterCirc = 0.5 * pi * r_tire      # length of a quarter of a tire, distance from one to the next encoder
    
    FL = 0 #front left wheel encoder counter
    FR = 0 #front right wheel encoder counter
    BL = 0 #back left wheel encoder counter
    BR = 0 #back right wheel encoder counter

    imu_drift = 0.0       # simulates yaw-sensor drift over time (slow sine)

    modelParams     = ModelParams()
    # modelParams.l_A = copy(get_param("L_a"))      # always throws segmentation faults *after* execution!!! ??
    # modelParams.l_B = copy(get_param("L_a"))
    # modelParams.m   = copy(get_param("m"))
    # modelParams.I_z = copy(get_param("I_z"))

    modelParams.l_A = 0.125
    modelParams.l_B = 0.125
    modelParams.m = 1.98
    modelParams.I_z = 0.24

    println("Publishing sensor information. Simulator running.")
    imu_data    = Imu()
    vel_est = Float32Msg()
    t0 = time()
    while ! is_shutdown()

        t = time()
        # update current state with a new row vector
        z_current[i,:],slip_ang[i,:]  = simDynModel_exact_xy(z_current[i-1,:],u_current', dt, modelParams)
        #println("z_current:")
        #println(z_current[i,:])
        #println(slip_ang[i,:])

        z_real.t[i]     = t
        slip_a.t[i]     = t

        # Encoder measurements calculation
        dist_traveled += z_current[i,3]*dt #count the total traveled distance since the beginning of the simulation
        if dist_traveled - last_updated >= quarterCirc
            last_updated = dist_traveled
            FL += 1
            FR += 1
            BL += 1
            BR += 0 #no encoder on back right wheel
            enc_data = Encoder(FL, FR, BL, BR)
            publish(pub_enc, enc_data) #publish a message everytime the encoder counts up
        end

        # IMU measurements
        imu_drift   = (t-t0)/100#sin(t/100*pi/2)     # drifts to 1 in 100 seconds
        yaw         = z_current[i,5] + randn()*0.05 + imu_drift
        psiDot      = z_current[i,6] + 0.01*randn()
        imu_data.orientation = geometry_msgs.msg.Quaternion(cos(yaw/2), sin(yaw/2), 0, 0)
        imu_data.angular_velocity = Vector3(0,0,psiDot)

        # Velocity measurement
        vel_est.data = convert(Float32,norm(z_current[i,3:4])+0.01*randn())
        if i%2 == 0
            imu_meas.i += 1
            imu_meas.t[imu_meas.i] = t
            imu_meas.z[imu_meas.i,:] = [yaw psiDot]
            publish(pub_imu, imu_data)      # Imu format is defined by ROS, you can look it up by google "rosmsg Imu"
                                            # It's sufficient to only fill the orientation part of the Imu-type (with one quaternion)
            publish(pub_vel, vel_est)

        end

        # GPS measurements
        x = round(z_current[i,1]*100 + 1*randn()*2)       # Indoor gps measures in cm
        y = round(z_current[i,2]*100 + 1*randn()*2)
        if i % 7 == 0
            gps_meas.i += 1
            gps_meas.t[gps_meas.i] = t
            gps_meas.z[gps_meas.i,:] = [x y]
            gps_data = Vector3(x,y,0)
            publish(pub_gps, gps_data)
        end

        i += 1
        rossleep(loop_rate)
    end

    # Clean up buffers

    clean_up(gps_meas)
    clean_up(imu_meas)
    clean_up(cmd_log)
    z_real.z[1:i-1,:] = z_current[1:i-1,:]
    slip_a.z[1:i-1,:] = slip_ang[1:i-1,:]
    z_real.i = i
    slip_a.i = i
    clean_up(z_real)
    clean_up(slip_a)

    # Save simulation data to file
    log_path = "$(homedir())/simulations/output.jld"
    save(log_path,"gps_meas",gps_meas,"z",z_real,"imu_meas",imu_meas,"cmd_log",cmd_log,"slip_a",slip_a)
    println("Exiting node... Saving data to $log_path. Simulated $((i-1)*dt) seconds.")
    #writedlm(log_path,z_current[1:i-1,:])
end

if ! isinteractive()
    main()
end
