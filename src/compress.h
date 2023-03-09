/*
 * Copyright (c) 2021, NVIDIA CORPORATION.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-FileCopyrightText: Copyright (c) 2021 NVIDIA CORPORATION
 * SPDX-License-Identifier: Apache-2.0
 */

//-------------------------------------------------------------------------------------------------
// This file can compress normal or tangent to a single uint
// all oct functions derived from:
// "A Survey of Efficient Representations for Independent Unit Vectors"
// http://jcgt.org/published/0003/02/01/paper.pdf

#pragma once

#ifndef COMPRESS_H
#define COMPRESS_H


#ifdef __cplusplus
#define INLINE inline
using namespace glm;

INLINE float roundEven(float x)
{
  int   Integer        = static_cast<int>(x);
  float IntegerPart    = static_cast<float>(Integer);
  float FractionalPart = (x - floor(x));

  if(FractionalPart > 0.5f || FractionalPart < 0.5f)
  {
    return std::round(x);
  }
  else if((Integer % 2) == 0)
  {
    return IntegerPart;
  }
  else if(x <= 0)  // Work around...
  {
    return IntegerPart - 1;
  }
  else
  {
    return IntegerPart + 1;
  }
}

#else
#define INLINE
#endif


//-----------------------------------------------------------------------
// Compression - can be done on host or device
//-----------------------------------------------------------------------

//////////////////////////////////////////////////////////////////////////
#define C_Stack_Max 3.402823466e+38f
extern uint compress_unit_vec(vec3 nv);

extern float short_to_floatm11(const int v);

extern vec3 decompress_unit_vec(uint packed);


#endif  // COMPRESS_H
