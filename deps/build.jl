version = "5.9.2"
bfpkg_url = "https://downloads.openmicroscopy.org/bio-formats/$version/artifacts/bioformats_package.jar"
download(bfpkg_url,joinpath(pwd(), "bioformats_package.jar"))

sb6_version = 20181120141755
sb6_url = "https://sites.imagej.net/SlideBook/jars/bio-formats/SlideBook6Reader.jar-$(sb6_version)"
download(sb6_url,joinpath(pwd(), "SlideBook6Reader.jar"))
