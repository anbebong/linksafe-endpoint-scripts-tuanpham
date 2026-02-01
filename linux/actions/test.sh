#!/bin/bash

# $1, $2, $3 là các tham số theo thứ tự bạn gõ sau lệnh
PARAM_NAME=${1:-"Chưa nhập"}  # Nếu không có $1 thì lấy "Chưa nhập"
VALUE=${2:-"N/A"}            # Nếu không có $2 thì lấy "N/A"
RETRY_COUNT=${3:-0}          # Nếu không có $3 thì lấy 0

# Màu sắc
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' 

echo -e "Doi 10s nhe "
sleep 10

echo -e "${CYAN}========================================${NC}"
echo -e "${YELLOW}   KẾT QUẢ NHẬN THAM SỐ (VỊ TRÍ)${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "Tham số 1 ($1) -> ParamName : $PARAM_NAME"
echo -e "Tham số 2 ($2) -> Value     : $VALUE"
echo -e "Tham số 3 ($3) -> Retry     : $RETRY_COUNT"

echo -e "${CYAN}========================================${NC}"
