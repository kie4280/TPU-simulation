module SystolicArray(
  input              clk,
  input [7:0]        M,
  input [7:0]        N,
  input [7:0]        K,
  output reg [15:0]  A_index,
  input [31:0]       A_data,
  output reg [15:0]  B_index,
  input [31:0]       B_data,
  output reg [15:0]  C_index,
  output reg [127:0] C_data_out,
  output reg         C_wr_en,
  input              enable,
  output reg         busy
);

parameter ar_size = 4;

parameter STATE_RESET      = 0;
parameter STATE_BUSY       = 1;
parameter STATE_PAUSE      = 2;
parameter STATE_WRITE      = 3;
parameter STATE_IDLE       = 4;

reg [15:0] counter;
reg [15:0] counter_stop;
reg [2:0] cur_state = STATE_IDLE;
reg [2:0] next_state = STATE_IDLE;

wire [7:0] inter_row [0:ar_size][0:ar_size-1];
wire [7:0] inter_col [0:ar_size-1][0:ar_size];
wire [127:0] results [0:ar_size][0:ar_size];
reg [7:0] top_data [0:ar_size-1][0:ar_size-1];
reg [7:0] left_data [0:ar_size-1][0:ar_size-1];

reg PE_clear = 1'b1;
reg PE_enable = 1'b0;

generate
genvar i, j;
  for(i=0; i < ar_size; i=i+1) begin 
    for(j=0; j < ar_size; j=j+1) begin
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

  for(i=0; i < ar_size; i=i+1) begin
    assign inter_col[i][0] = left_data[i][0];
  end
  for (j=0; j < ar_size; j=j+1) begin
    assign inter_row[0][j] = top_data[0][j];
  end
endgenerate


always @(posedge clk, posedge enable) begin
  if (cur_state == STATE_WRITE 
    || cur_state == STATE_BUSY
    || cur_state == STATE_RESET
    || cur_state == STATE_PAUSE
    || enable) begin
    busy = 1;
  end
  else begin
    busy = 0;
  end
end


always @(posedge clk) begin
  cur_state <= next_state; 
end

always @(*) begin
case (cur_state)
  STATE_RESET: begin
    next_state = STATE_BUSY;
  end
  
  STATE_BUSY: begin
    if (counter >= counter_stop) begin
      next_state = STATE_PAUSE;
    end

  end

  STATE_PAUSE: begin
    next_state = STATE_WRITE;
  end

  STATE_WRITE: begin
    if (counter >= counter_stop) begin
      next_state = STATE_IDLE;
    end

  end

  STATE_IDLE: begin
    if (enable) 
      next_state = STATE_RESET;

  end

  default:;

endcase
end


always @(posedge clk) begin
case (cur_state)

  STATE_RESET: begin
    A_index <= 0;
    B_index <= 0;
    C_index <= 0;
    C_wr_en <= 0;
    counter <= 0;
    PE_clear <= 0;
    PE_enable <= 1;
    counter_stop <= K + 8 - 1;
    for (integer i=0; i < ar_size; i=i+1) begin
      for (integer j=0; j < ar_size; j=j+1) begin
        top_data[i][j] <= 0;
        left_data[i][j] <= 0;
      end
    end
  end

  STATE_BUSY: begin
    counter <= counter + 1;
    A_index <= counter + 1;
    B_index <= counter + 1;

    for (integer i=0; i < ar_size; i=i+1) begin
      top_data[i][i] <= (counter < K ? B_data[31-i*8 -: 8] : 32'd0);
      left_data[i][i] <= (counter < K ? A_data[31-i*8 -: 8] : 32'd0);

      for (integer j=0; j < i; j=j+1) begin
        top_data[j][i] <= top_data[j+1][i];
        left_data[i][j] <= left_data[i][j+1];

      end
    end
  end

  STATE_PAUSE: begin
    counter <= 0;
    counter_stop <= 4-1;
    PE_enable <= 0;

  end

  STATE_WRITE: begin
    counter <= counter + 1;
    C_wr_en <= 1;
    C_index <= counter;
    C_data_out <= {
      results[counter][0][31:0],
      results[counter][1][31:0],
      results[counter][2][31:0],
      results[counter][3][31:0]
    };

  end

  STATE_IDLE: begin
    PE_enable <= 0;
    PE_clear <= 1;
    counter <= 0;
    counter_stop <= 0;
    C_wr_en <= 0;

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

wire [31:0] mul;
assign mul = left * top;

always @(posedge clk or posedge clear) begin
  if (clear == 1) begin
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
