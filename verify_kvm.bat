@echo off
chcp 65001 >nul
setlocal
set OUT=kvm_verify_result.txt
echo ============================================
echo   等待设备上线（插好 USB，最多等 3 分钟）
echo   探针内核花屏/黑屏是正常的
echo ============================================
adb wait-for-device
echo 设备已上线，开始采集...
echo.

(
echo ===== 内核版本 =====
adb shell cat /proc/version
echo.
echo ===== EL / KVM 初始化 =====
adb shell dmesg ^| grep -iE "started at EL|Hyp mode|vgic|GICv3|kvm" ^| head -n 40
echo.
echo ===== /dev/kvm =====
adb shell ls -l /dev/kvm
adb shell grep -i kvm /proc/misc
echo.
echo ===== uptime =====
adb shell uptime
echo.
echo ===== 推送并运行 KVM 自检 =====
adb push kvmtest_user /data/local/tmp/kvmtest_user
adb shell chmod 755 /data/local/tmp/kvmtest_user
adb shell /data/local/tmp/kvmtest_user
echo.
echo ===== dmesg 尾部 =====
adb shell dmesg ^| tail -n 30
) > "%OUT%" 2>&1

type "%OUT%"
echo.
echo ============================================
echo   结果已保存到 %OUT%
echo   把这个文件的内容贴给 AI 即可
echo ============================================
pause