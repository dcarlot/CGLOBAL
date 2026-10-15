set McprDir=%CD%

pushd .
cd %CommonProgramW6432%\mcafee\casper
mfeamcin.exe -u -x mfeavsinst_vso16.xml -l "%McprDir%\casper_uninstall_newIstaller.log"
popd

pushd .
cd %CommonProgramW6432%\mcafee\AMCoreInstall
mfeamcin.exe -u -x mfeavsinst_lam.xml -l "%McprDir%\amcore_lam_uninstall_newInstaller.log"
popd

pushd .
cd %CommonProgramW6432%\mcafee\casper
installer.exe -u -x mfeavsinst_vso16.xml -l "%McprDir%\casper_uninstall.log"
popd

pushd .
cd %CommonProgramW6432%\mcafee\AMCoreInstall
installer.exe -u -x mfeavsinst_lam.xml -l "%McprDir%\amcore_lam_uninstall.log"
popd


pushd .
cd casper\latest\64
mfeamcin.exe -u -x mfeavsinst.xml -l casper_uninstall_latest.log
popd

pushd .
cd casper\latest\64
mfeamcin.exe -u -x mfeavsinst_lam.xml -l amcore_lam_uninstall_latest.log
popd


pushd.
cd casper\2.6\64
installer.exe -u -x mfeavsinst.xml -l casper_uninstall.log
popd