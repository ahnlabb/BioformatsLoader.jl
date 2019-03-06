version = "5.7.3"
bfpkg_url = "https://downloads.openmicroscopy.org/bio-formats/$version/artifacts/bioformats_package.jar"
download(bfpkg_url, joinpath(pwd(), "bioformats_package.jar"))

xsd_version = "2016-06"
xsd_url = "https://www.openmicroscopy.org/Schemas/OME/$xsd_version/ome.xsd"
download(xsd_url, joinpath(pwd(), "ome.xsd"))
