# 
# Usage: To re-create this platform project launch xsct with below options.
# xsct C:\Users\weitong\Desktop\adsingle\ws\ad_single_1\platform.tcl
# 
# OR launch xsct and run below command.
# source C:\Users\weitong\Desktop\adsingle\ws\ad_single_1\platform.tcl
# 
# To create the platform in a different location, modify the -out option of "platform create" command.
# -out option specifies the output directory of the platform project.

platform create -name {ad_single_1}\
-hw {C:\Users\weitong\Desktop\adsingle\vivado\adau1979_lwip\ad_single_1.xsa}\
-proc {ps7_cortexa9_0} -os {standalone} -out {C:/Users/weitong/Desktop/adsingle/ws}

platform write
platform generate -domains 
platform active {ad_single_1}
platform generate
