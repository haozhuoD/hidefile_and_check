cmd_/home/dhz/my_lkm/docheck/Module.symvers := sed 's/ko$$/o/' /home/dhz/my_lkm/docheck/modules.order | scripts/mod/modpost -m -a   -o /home/dhz/my_lkm/docheck/Module.symvers -e -i Module.symvers   -T -
