# RV32I-Multi-Cycle-CPU-AMBA-APB-Peripheral

## System Architecture
<img width="946" height="440" alt="Image" src="https://github.com/user-attachments/assets/6439a9a2-a5e9-457f-b57d-1f4ce0ffe0c1" />
<br>

## 특징
### 1. 동작 방식
#### 각 명령어가 여러 클록 사이클에 걸쳐 실행된다.
#### 각 사이클마다 한 단계씩 진행하며, 명령어마다 필요한 사이클 수가 다르다.
<br>

### 2. 구성 요소
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
