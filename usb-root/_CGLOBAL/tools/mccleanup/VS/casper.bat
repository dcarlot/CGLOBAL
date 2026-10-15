set McprDir=%CD%

pushd .
cd %programfiles%\common files\mcafee\casper
mfeamcin.exe -u -x mfeavsinst_vso16.xml -l "%McprDir%\casper_uninstall_newIstaller.log"
popd

pushd .
cd %programfiles%\common files\mcafee\AMCoreInstall
mfeamcin.exe -u -x mfeavsinst_lam.xml -l "%McprDir%\amcore_lam_uninstall_newInstaller.log"
popd

pushd .
cd %programfiles%\common files\mcafee\casper
installer.exe -u -x mfeavsinst_vso16.xml -l "%McprDir%\casper_uninstall.log"
popd


pushd .
cd %programfiles%\common files\mcafee\AMCoreInstall
installer.exe -u -x mfeavsinst_lam.xml -l "%McprDir%\amcore_lam_uninstall.log"
popd


pushd .
cd casper\latest\32
mfeamcin.exe -u -x mfeavsinst.xml -l casper_uninstall_latest.log
popd

pushd .
cd casper\latest\32
mfeamcin.exe -u -x mfeavsinst_lam.xml -l amcore_lam_uninstall_latest.log
popd

pushd.
cd casper\2.6\32
installer.exe -u -x mfeavsinst.xml -l casper_uninstall.log
popd