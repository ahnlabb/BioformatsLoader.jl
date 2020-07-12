version = "6.5.1"
bfpkg_url = "https://downloads.openmicroscopy.org/bio-formats/$version/artifacts/bioformats_package.jar"
@info "Downloading version $version of bioformats_package.jar from $bfpkg_url"
download(bfpkg_url, joinpath(pwd(), "bioformats_package.jar"))

xsd_version = "2016-06"
xsd_url = "https://www.openmicroscopy.org/Schemas/OME/$xsd_version/ome.xsd"
@info "Downloading version $xsd_version of ome.xsd from $xsd_url"
download(xsd_url, joinpath(pwd(), "ome.xsd"))
