// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
//
// Description: Clock divider to provide clock enables for 
//              devices.
//
// Author.....: Alan Garfield
//              Niels A. Moseley
// Date.......: 29-1-2018
//

module clock
(
   input sys_clock,        // master clock
   input reset,            // reset

   // Clock enables
   output reg cpu_clken    // 1MHz clock enable for the CPU and devices
);

	reg [7:0] clk_div;
	always @(posedge sys_clock or posedge reset)
	begin
	   if(reset) begin
			clk_div <= 0;
		end
		else begin			
			if (clk_div == 6)
				clk_div <= 0;
			else
				clk_div <= clk_div + 1;

			cpu_clken <= (clk_div[7:0] == 0);
		end
	end

endmodule
