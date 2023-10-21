`define STATE_RESET 2'd0
`define STATE_BUSY 2'd1
`define STATE_WRITE 2'd2
`define STATE_FINISHED 2'd3


module TPU(
  input clk,
  input rst_n,
  input              in_valid,
  input [7:0]        K,
  input [7:0]        M,
  input [7:0]        N,
  output reg         busy,

  output             A_wr_en,
  output reg [15:0]  A_index,
  output [31:0]      A_data_in,
  input  [31:0]      A_data_out,

  output             B_wr_en,
  output reg [15:0]  B_index,
  output [31:0]      B_data_in,
  input  [31:0]      B_data_out,

  output reg         C_wr_en,
  output reg [15:0]  C_index,
  output reg [127:0] C_data_in,
  input  [127:0]     C_data_out
);

parameter n_rows=4;
parameter n_cols=4;


//* Implement your design here

reg [7:0] K_reg;
reg [7:0] M_reg;
reg [7:0] N_reg;

reg [15:0] counter;
reg [15:0] counter_stop;
reg [1:0] state = `STATE_RESET;

assign A_wr_en = 1'b0;
assign B_wr_en = 1'b0;

wire [7:0] inter_row [0:n_rows][0:n_cols-1];
wire [7:0] inter_col [0:n_rows-1][0:n_cols];
wire [127:0] results [0:n_rows][0:n_cols];

reg [7:0] top_data [0:n_rows-1][0:n_cols-1];
reg [7:0] left_data [0:n_rows-1][0:n_cols-1];

reg PE_clear = 1'b1;
reg PE_enable = 1'b0;

generate
genvar i, j;
  for(i=0; i < n_rows; i=i+1) begin 
    for(j=0; j < n_cols; j=j+1) begin
      PE u_pe(
        clk,
        PE_clear, 
        PE_enable,
        inter_col[i][j],
        inter_row[i][j],
        inter_col[i][j+1],
        inter_row[i+1][j],
        results[i][j]
      );
    end
  end

  for(i=0; i < n_rows; i=i+1) begin
    assign inter_col[i][0] = left_data[i][0];
  end
  for (j=0; j < n_cols; j=j+1) begin
    assign inter_row[0][j] = top_data[0][j];
  end
endgenerate

always @(posedge clk, negedge rst_n) begin
  if (~rst_n) begin
    busy <= 0;
  end
  else if (in_valid) begin
    busy <= 1;
  end
  else if (state == `STATE_FINISHED) begin
    busy <= 0;
  end
end



always @(posedge clk) begin
  if (in_valid) begin
    state = `STATE_BUSY;
    counter <= 0;
    counter_stop <= K*M-1;
    PE_enable = 1;
    PE_clear = 0;
  end
  else if (busy && state == `STATE_BUSY) begin

    if (counter >= counter_stop) begin
      state = `STATE_WRITE;
      counter <= 0;
      counter_stop <= K_reg-1;
    end
    else begin
      counter <= counter + 1;
    end

  end
  else if (busy && state == `STATE_WRITE) begin
    if (counter >= counter_stop) begin
      counter <= 0;
      state = `STATE_FINISHED;
    end
    else begin
      counter <= counter + 1;
    end
  end
  else if (~busy) begin
    state = `STATE_RESET;
  end
end


reg [15:0] index;

always @(posedge clk) begin
  case (state)

  `STATE_RESET: begin
    K_reg <= K;
    M_reg <= M;
    N_reg <= N;
    A_index = 0;
    B_index = 0;
    C_index = 0;
    C_wr_en = 0;
    for (integer i=0; i < n_rows; i=i+1) begin
      for (integer j=0; j < n_cols; j=j+1) begin
        top_data[i][j] <= 0;
        left_data[i][j] <= 0;
      end
    end
  end

  `STATE_BUSY: begin
    PE_enable = 1;
    PE_clear = 0;
    A_index <= counter + 1;
    B_index <= counter + 1;

    for (integer i=0; i < n_rows; i=i+1) begin
      top_data[i][i] <= B_data_out[31-i*8 -: 8];
      left_data[i][i] <= A_data_out[31-i*8 -: 8];
      for (integer j=0; j < i; j=j+1) begin
        top_data[j][i] <= top_data[j+1][i];
        left_data[i][j] <= left_data[i][j+1];

      end
    end


  end

  `STATE_FINISHED: begin
    PE_enable <= 0;
    PE_clear <= 1;

  end

  `STATE_WRITE: begin
    C_wr_en <= 1;
    C_index <= counter;
    C_data_in <= {
      results[counter][0][31:0],
      results[counter][1][31:0],
      results[counter][2][31:0],
      results[counter][3][31:0]
    };

  end


  default: ;
  endcase
end


endmodule



module PE(
  input clk,
  input clear,
  input enable,
  input [7:0] left,
  input [7:0] top,
  output reg [7:0] right,
  output reg [7:0] bottom,
  output reg [127:0] result
); 

wire mul;
assign mul = left * top;

always @(posedge clk or posedge clear) begin
  if (clear == 1'b1) begin
    result <= 0;
    right <= 0;
    bottom <= 0;
  end 
  else if (enable) begin
    right <= left;
    bottom <= top;
    result <= result + mul;

  end

end


endmodule
