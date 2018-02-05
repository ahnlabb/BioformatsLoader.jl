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
using BioFormats
using Images

try
        JavaCall.init(["-ea", "-Xmx1024M", "-Djava.class.path=/path/to/bioformats_package.jar"])
end

image = bf_import("file.msr")
```

where `/path/to/bioformats_package.jar` should be changed to fit your setup.
