echo Start
date
for sn in `seq -w 1 100`;do
    echo "=========== $sn - 1 ==============="
    date
    rm BinaryCurrent
    ln -sf BinaryAsBuilt BinaryCurrent
    ls -ltrhd BinaryCurrent
    ./DPOut_DPTX_firmware_load.pl
    ./DPOut_DPRX_firmware_load.pl
    ./DPOut_Splitter_firmware_load.pl
    echo "=========== $sn - 2 ==============="
    date
    rm BinaryCurrent
    ln -sf Binary20180612 BinaryCurrent
    ls -ltrhd BinaryCurrent
    ./DPOut_DPTX_firmware_load.pl
    ./DPOut_DPRX_firmware_load.pl
    ./DPOut_Splitter_firmware_load.pl
done
