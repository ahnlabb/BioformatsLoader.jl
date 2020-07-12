# BioformatsLoader

[![Build Status](https://travis-ci.org/ahnlabb/BioformatsLoader.jl.svg?branch=master)](https://travis-ci.org/ahnlabb/BioformatsLoader.jl)

[![Coverage Status](https://coveralls.io/repos/ahnlabb/BioformatsLoader.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/ahnlabb/BioformatsLoader.jl?branch=master)

[![codecov.io](http://codecov.io/github/ahnlabb/BioformatsLoader.jl/coverage.svg?branch=master)](http://codecov.io/github/ahnlabb/BioformatsLoader.jl?branch=master)

## Dependencies

Depends on `bioformats_package.jar`

## Install

```julia
using Pkg
Pkg.add(url="https://github.com/ahnlabb/BioformatsLoader.jl") # Change if forked
```

Inside the Julia interactive REPL, you can also use
```julia
julia>]add https://github.com/ahnlabb/BioformatsLoader.jl
```

## Build Process

The add command will invoke `Pkg.build("BioformatsLoader")` which will download `bioformats_package.jar` and `ome.xsd` into the `deps` folder. You can use another copy of `bioformats_package.jar` by manually configuring the class path. See Advanced Usage below.

## Setup Environment

Set the environmental variable `JULIA_COPY_STACKS` to `1`. On Linux and Mac, this can be done by invoking julia in the following way:

```bash
$ JULIA_COPY_STACKS=1 julia
```

## Basic Usage

```julia
using BioformatsLoader
BioformatsLoader.init() # Initializes JavaCall with opt and classpath
image = bf_import("file.msr") # Import the image file.msr
copy(image[1].data) # Get a standard Julia 2D array
```

## Advanced Usage

```julia
using BioformatsLoader
using JavaCall

JavaCall.addClassPath(BioformatsLoader.get_bf_path())
# Alternatively, use bioformats_package.jar of at an alternate path
# JavaCall.addClassPath("/path/to/bioformats_package.jar")
# Add other classpath values here

# Setup options
JavaCall.addOpts("-ea") # Enable assertions
JavaCall.addOpts("-Xmx1024M") # Set maximum memory to 1 Gigabyte
# Add other options here

try
        JavaCall.init()
end
```

To import the file `file.msr` you then do

```julia
image = bf_import("file.msr")
```

The variable `image` will contain an array of ImageMetadata, the data will be the type that the format specifies: __Int8__, __UInt8__, __Int16__, __UInt16__, __Int32__, __UInt32__, __Float32__, __Float64__ or __Bool__.

If you just want a plain array of the first frame:

```julia
plain_array = copy(image[1].data)
```

## Viewing Images

Any package that will display a 2D array can be used to view the images. For example, you can use [ImageView](https://github.com/JuliaImages/ImageView.jl):

```julia
using ImageView
imshow(image[1].data)
```
