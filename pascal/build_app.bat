fpc -B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq ^
  -Fu.\std -Fu.\std\qar -Fu.\std\platform -Fu.\std\config -Fu.\std\io -Fu.\std\log -Fu.\app ^
  -FE.\app -oqjsp.exe ^
  app\qjsp.pas

fpc -B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq ^
  -Fu.\std -Fu.\std\qar -Fu.\std\platform -Fu.\std\config -Fu.\std\io -Fu.\std\log -Fu.\app ^
  -FE.\app -oqar_tool.exe ^
  app\qar_tool.pas


fpc -B -Mobjfpc -Scghi -O2 -Xs -XX -l -vewnhibq ^
  -Fu.\std -Fu.\std\qar -Fu.\std\platform -Fu.\std\config -Fu.\std\io -Fu.\std\log -Fu.\app ^
  -FE.\app -oqstability_test_runner.exe ^
  app\stability_test_runner.pas