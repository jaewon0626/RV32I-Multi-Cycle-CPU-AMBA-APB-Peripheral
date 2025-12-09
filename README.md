# RV32I-Multi-Cycle-CPU-AMBA-APB-Peripheral
### AMBA(Advanced Microcontroller Bus Architecture)
> ARM에서 제안한 SoC (System-on-Chip) 내부 버스 표준 규격, CPU, 메모리, 주변장치(IP 블록) 간 데이터를 효율적으로 주고받게 해주는 연결 규칙
> <img width="343" height="136" alt="image" src="https://github.com/user-attachments/assets/ed7629c2-8dd1-4600-abd1-d6f2207b666f" />

## System Architecture
<img width="1129" height="529" alt="image" src="https://github.com/user-attachments/assets/65ef64c3-8e78-4470-8cc4-88b5e2166d55" 
<br>

## 특징
### 1. APB란?
#### APB(Advanced Peripheral Bus)
> AMBA 버스중 가장 단순한 저속용 버스 -> 저속 주변장치용 제어버스
> Master와 Slave가 같은 타이밍 규약과 신호 정의를 지켜 통신하도록 설계됨
> AHB나 AXI 처럼 복잡한 데이터 전송보단, 단순히 레지스터에 Read/Write하는 기능에 초점을 맞춘 구조
> <br>
> AXI나 AHB는 GPIO, UART, FND, TIMER 같은 저속 제어 장치에는 불필요하게 복잡, 전력 소모 ↑ -> SoC 전체 성능과 효율을 높이기 위해 저속 장치들은 APB 버스로 연결 
<img width="460" height="171" alt="image" src="https://github.com/user-attachments/assets/5926296e-d3e3-4ba9-8d07-8ad21ef2d4cf" />
<img width="723" height="221" alt="image" src="https://github.com/user-attachments/assets/dfcebd75-c139-4ae2-b79a-9e5d80485906" />
<br>

### 2. APB 동작 방식
<img width="743" height="344" alt="image" src="https://github.com/user-attachments/assets/838d2234-3624-4db6-b5b1-c7d453c25129" />


#### 클록 주기 : 가장 짧은 단계의 실행 시간에 맞춰 설정할 수 있어 훨씬 짧다.

#### 하드웨어 구조 : 하드웨어 유닛을 공유한다. (하나의 메모리, 하나의 ALU 등)

#### 제어 유닛 (Control Unit)의 특징 :
##### FSM (Finite State Machine) 기반: 멀티사이클 프로세서는 상태 기반 제어를 사용한다.
##### 상태 전이 : 현재 상태와 명령어 타입에 따라 다음 상태로 전이한다.
##### 제어 신호 생성 : 각 상태에서 필요한 제어 신호(IRWrite, PCWrite, MemRead, RegWrite, ALUSrcA, ALUSrcB 등)를 생성한다.
##### 명령어별 경로 : R-type은 4사이클, Load는 5사이클, Branch는 3사이클 등 명령어마다 다른 상태 경로를 거친다.

#### 데이터패스(Datapath) :
##### - Cycle 1 - IF : 명령어 메모리에서 명령어를 읽어 IR(Instruction Register)에 저장하고, PC를 PC + 4로 업데이트한다.
##### - Cycle 2 - ID : IR의 명령어를 디코딩하고, 레지스터 파일에서 rs1, rs2를 읽어 임시 레지스터(A, B)에 저장합니다. 즉시값(Immediate)도 생성하여 저장한다.
##### - Cycle 3 - EX : ALU가 A, B 레지스터 값을 사용해 연산을 수행하고 결과를 ALUOut 레지스터에 저장합니다. Branch의 경우 분기 타겟 주소를 계산한다.
##### - Cycle 4 - MEM (Load/Store) : ALUOut의 주소를 사용해 데이터 메모리에 접근합니다. Load는 읽은 값을 MDR(Memory Data Register)에 저장하고, Store는 메모리에 쓴다.
##### - Cycle 5 - WB (Register write 명령어만) : ALUOut 또는 MDR의 값을 레지스터 파일의 rd에 쓴다.
<br>

### 3. 장단점
#### 장점
##### 클록 주기가 짧아 성능 향상이 가능하다.
##### 하드웨어 자원을 효율적으로 공유하여 면적이 줄어든다.
##### 명령어별로 필요한 만큼만 사이클을 사용한다.
##### 전력 소모가 상대적으로 적다.


#### 단점
##### 제어 로직이 복잡하다 (FSM 설계 및 상태 관리 필요)
##### 명령어마다 실행 시간이 달라 타이밍 예측이 어렵다.
##### 단계 간 데이터 저장을 위한 추가 레지스터가 필요하다 (IR, A, B, ALUOut, MDR)
##### 디버깅이 더 복잡하다.
