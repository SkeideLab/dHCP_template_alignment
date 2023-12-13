#!/bin/bash

# script to align native surfaces with template space & resample native surfaces with template topology
# output: native giftis resampled with template topology
set -x -u -e
Usage() {
    echo "align_to_template.sh <topdir> <subjid> <session> <age> <volumetric template> <volumetric template name> <surface template> <surface template name> <pre_rotation> <outdir>  <config> <script dir> < MSM bin> <wb bin>"
    echo " script to align native surfaces with template space & resample native surfaces with template topology "
    echo " input args: "
    echo " topdir: top directory where subject directories are located "
    echo " subjid : subject id "
    echo " session: subject scan session "
    echo " age: in weeks gestation - this will determine which week of the spatio-temporal template the data will first mapped to"
    echo " template volume: template T2 40 week volume "
    echo " volumetric template name: extdhcp40wk or dhcp40wk"
    echo " surface template: path to the top level directory of the dHCP surface template"
    echo " surface template name: dhcpSym or dhcpASym"
    echo " pre_rotation : txt file containing rotational transform between MNI and FS_LR space (i.e. file rotational_transforms/week40_toFS_LR_rot.%hemi%.txt  ) "
    echo " outdir : base directory where output will be sent "
    echo " config : base config file "
    echo " script dir: path to scripts"
    echo " MSM bin: msm binary"
    echo " wb bin : workbench binary"
    echo "mirtk bin : mirtk binary "
    echo "output: 1) surface registrations; 2)  native giftis resampled with template topology "
}

#FIXME Are the prerotations dependent on the template that has been used in the template40wk warp?
# if yes, which has been used in my data and which has been used to make the repo?
# should we just re-estimate them anyway?

if [ "$#" -lt 11 ]; then
    echo "$#"
    Usage
    exit
fi

topdir=$1
shift
subjid=$1
shift
session=$1
shift
age=$1
shift
templatevolume=$1
shift
templatevolumename=$1
shift
templatespherepath=$1
shift
templatespherename=$1
shift
pre_rotation=$1
shift
outdir=$1
shift
config=$1
shift
SURF2TEMPLATE=$1
shift
MSMBIN=$1
shift
WB_BIN=$1
shift
mirtk_BIN=$1
shift

########## DEFINE PATHS TO VARIABLES ##########

#inputs
nativedir=${topdir}/sub-${subjid}/ses-$session/anat
native_volume=${nativedir}/sub-${subjid}_ses-${session}_desc-restore_T2w.nii.gz
native_sphere=${nativedir}/sub-${subjid}_ses-${session}_hemi-%hemi%_space-T2w_sphere.surf.gii
native_data=${nativedir}/sub-${subjid}_ses-${session}_hemi-%hemi%_space-T2w_sulc.shape.gii

# inputs (template)
template00wk_sphere=$templatespherepath/week-${age}_hemi-%hemi%_space-${templatespherename}_dens-32k_sphere.surf.gii
template00wk_data=$templatespherepath/week-${age}_hemi-%hemi%_space-${templatespherename}_dens-32k_sulc.shape.gii
template40wk_midthickness=$templatespherepath/week-40_hemi-%hemi%_space-${templatespherename}_dens-32k_midthickness.surf.gii
template40wk=$templatespherepath/week-40_hemi-%hemi%_space-${templatespherename}_dens-32k_sphere.surf.gii

#outputs
sub_templatespace_dir=${outdir}/sub-${subjid}/ses-$session/space-${templatespherename}_32k
mkdir -p $sub_templatespace_dir/volume_dofs $sub_templatespace_dir/surface_transforms
native_rot_sphere=${nativedir}/sub-${subjid}_ses-${session}_hemi-%hemi%_space-fslr_sphere.rot.surf.gii
outname=$sub_templatespace_dir/surface_transforms/sub-${subjid}_ses-${session}_hemi-%hemi%_from-native_to-${templatespherename}40_dens-32k_mode-
transformed_sphere=${outname}sphere.reg40.surf.gii

for hemi in left right; do

    # capitalize and extract first letter of hemi (left --> L)
    hemi_upper_tmp=${hemi:0:1}
    hemi_upper=${hemi_upper_tmp^}

    # swap in correct hemisphere label
    pre_rotation_hemi=$(echo ${pre_rotation} | sed "s/%hemi%/$hemi_upper/g")
    native_sphere_hemi=$(echo ${native_sphere} | sed "s/%hemi%/$hemi_upper/g")
    native_data_hemi=$(echo ${native_data} | sed "s/%hemi%/$hemi_upper/g")
    template00wk_sphere_hemi=$(echo ${template00wk_sphere} | sed "s/%hemi%/$hemi/g")
    template00wk_data_hemi=$(echo ${template00wk_data} | sed "s/%hemi%/$hemi/g")
    template40wk_hemi=$(echo ${template40wk} | sed "s/%hemi%/$hemi/g")
    template40wk_midthickness_hemi=$(echo ${template40wk_midthickness} | sed "s/%hemi%/$hemi/g")
    native_rot_sphere_hemi=$(echo ${native_rot_sphere} | sed "s/%hemi%/$hemi_upper/g")
    outname_hemi=$(echo ${outname} | sed "s/%hemi%/$hemi_upper/g")
    transformed_sphere_hemi=$(echo ${transformed_sphere} | sed "s/%hemi%/$hemi_upper/g")

    ########## ROTATE LEFT AND RIGHT HEMISPHERES INTO APPROXIMATE ALIGNMENT WITH MNI SPACE ##########
    ${SURF2TEMPLATE}/surface_to_template_alignment/pre_rotation.sh \
        $native_volume \
        $native_sphere_hemi \
        $templatevolume \
        $pre_rotation_hemi \
        $sub_templatespace_dir/volume_dofs/${subjid}-${session}_space-$templatevolumename.dof \
        $native_rot_sphere_hemi \
        $mirtk_BIN $WB_BIN

    ########## RUN MSM NON-LINEAR ALIGNMENT TO TEMPLATE FOR LEFT AND RIGHT HEMISPHERES ##########
    indata=$native_data_hemi
    inmesh=$native_rot_sphere_hemi
    refmesh=$template00wk_sphere_hemi
    refdata=$template00wk_data_hemi

    if [ ! -f ${transformed_sphere_hemi} ]; then

        ${MSMBIN} \
            --inmesh=${inmesh} \
            --refmesh=${refmesh} \
            --indata=${indata} \
            --refdata=${refdata} \
            -o ${outname_hemi} \
            --conf=${config} \
            --verbose

        if [ "$age" == "40" ]; then
            # rename to emphasize registration to 40 (sphere.reg40.surf.gii)
            mv ${outname_hemi}sphere.reg.surf.gii ${transformed_sphere_hemi}
        else
            # need to concatenate msm warp to local template with warp from local template to 40 week template
            ${WB_BIN} -surface-sphere-project-unproject \
                ${outname_hemi}sphere.reg.surf.gii \
                $refmesh \
                $templatespherepath/week-to-40-registrations/${hemi}.${age}-to-40/${hemi}.${age}-to-40sphere.reg.surf.gii \
                $transformed_sphere_hemi ### LZJW added hemi and changed filepath for between template ###
        fi

        # the output sphere represents the full warp from Native to 40 week template space - save this
        cp "$transformed_sphere_hemi" "$nativedir"

    fi

    ########## RESAMPLE TEMPLATE TOPOLOGY ON NATIVE SURFACES - OUTPUT IN '${templatespherename}_32k' DIRECTORY ##########
    # first copy the template sphere to the subjects ${templatespherename}_32k
    # Each subject's template space sphere IS the template! following HCP form.
    cp $template40wk_hemi $sub_templatespace_dir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-${templatespherename}_dens-32k_sphere.surf.gii

    # resample surfaces
    for surf in pial wm midthickness inflated veryinflated; do

        ${WB_BIN} -surface-resample \
            $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-T2w_${surf}.surf.gii \
            $transformed_sphere_hemi \
            $template40wk_hemi \
            ADAP_BARY_AREA \
            $sub_templatespace_dir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-${templatespherename}40_${surf}.surf.gii \
            -area-surfs \
            $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-T2w_midthickness.surf.gii \
            $template40wk_midthickness_hemi
    done

    # resample .shape metrics
    for metric in sulc curv thickness; do

        ${WB_BIN} -metric-resample \
            $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-T2w_${metric}.shape.gii \
            $transformed_sphere_hemi \
            $template40wk_hemi \
            ADAP_BARY_AREA \
            $sub_templatespace_dir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-${templatespherename}40_${metric}.shape.gii \
            -area-surfs \
            $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-T2w_midthickness.surf.gii \
            $template40wk_midthickness_hemi
    done ### LZJW changed output file name ###

    #resample metrics with nonstandard names
    ${WB_BIN} -metric-resample \
        $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_desc-corr_space-T2w_thickness.shape.gii \
        $transformed_sphere_hemi \
        $template40wk_hemi \
        ADAP_BARY_AREA \
        $sub_templatespace_dir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_desc-corr_space-${templatespherename}40_thickness.shape.gii \
        -area-surfs \
        $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-T2w_midthickness.surf.gii \
        $template40wk_midthickness_hemi

    ${WB_BIN} -metric-resample \
        $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_desc-medialwall_mask.shape.gii \
        $transformed_sphere_hemi \
        $template40wk_hemi \
        ADAP_BARY_AREA \
        $sub_templatespace_dir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_desc-medialwall_space-${templatespherename}40_mask.shape.gii \
        -area-surfs \
        $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-T2w_midthickness.surf.gii \
        $template40wk_midthickness_hemi

    # resample .label files
    ${WB_BIN} -label-resample \
        $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_desc-drawem_space-T2w_dparc.dlabel.gii \
        $transformed_sphere_hemi \
        $template40wk_hemi \
        ADAP_BARY_AREA \
        $sub_templatespace_dir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_desc-drawem_space-${templatespherename}40_dparc.dlabel.gii \
        -area-surfs \
        $nativedir/sub-${subjid}_ses-${session}_hemi-${hemi_upper}_space-T2w_midthickness.surf.gii \
        $template40wk_midthickness_hemi
done
