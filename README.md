# BioformatsLoader

[![Build Status](https://travis-ci.org/ahnlabb/BioformatsLoader.jl.svg?branch=master)](https://travis-ci.org/ahnlabb/BioformatsLoader.jl)

[![Coverage Status](https://coveralls.io/repos/ahnlabb/BioformatsLoader.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/ahnlabb/BioformatsLoader.jl?branch=master)

[![codecov.io](http://codecov.io/github/ahnlabb/BioformatsLoader.jl/coverage.svg?branch=master)](http://codecov.io/github/ahnlabb/BioformatsLoader.jl?branch=master)

## Usage

Requires `bioformats_package.jar`

```julia
Pkg.clone("https://github.com/ahnlabb/BioformatsLoader.jl")
```

```julia
using BioformatsLoader
using JavaCall

bfpkg_path = "/path/to/bioformats_package.jar"

try
        JavaCall.init(["-ea", "-Xmx1024M", "-Djava.class.path=$bfpkg_path"])
end
```

To import the file `file.msr` you then do

```julia
image = bf_import("file.msr")
```

The variable `image` will contain an array of ImageMetadata, the data will be the type that the format specifies: __Int8__, __UInt8__, __Int16__, __UInt16__, __Int32__, __UInt32__, __Float32__, __Float64__ or __Bool__.
