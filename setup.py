import os
from setuptools import Extension, setup

try:
    from Cython.Build import cythonize
except ImportError:
    cythonize = None

# hotfix astc_decomp.h import in astc_decomp.cpp
path = os.path.dirname(os.path.realpath(__file__))
fp = os.path.join(path, 'astc_dec', 'astc_decomp.cpp')
text = open(fp, 'rt', encoding='utf8').read()
open(fp, 'wt', encoding='utf8').write(text.replace('#include "basisu_astc_decomp.h"', '#include "astc_decomp.h"'))

extensions = [
    Extension(
        name="astc_decomp",
        sources=[
            "astc_decomp.pyx",
            "astc_dec/astc_decomp.cpp",
        ],
        language="c++",
        include_dirs=[
            "astc_dec"
        ],
    )
]
if cythonize:
    extensions = cythonize(extensions)

setup(ext_modules=extensions)
