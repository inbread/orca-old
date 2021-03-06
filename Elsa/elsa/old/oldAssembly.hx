package elsa;
import elsa.symbol.SymbolTable;
import elsa.Token.Type;
import elsa.symbol.Symbol;
import elsa.symbol.VariableSymbol;
import elsa.symbol.FunctionSymbol;
import elsa.symbol.ClassSymbol;
import elsa.symbol.LiteralSymbol;

/**
 * ...
 * @author 김 현준
 */
class Assembly {

	/**
	 * 심볼 테이블
	 */
	public var symbolTable:SymbolTable;
	
	/**
	 * 어셈블리 코드
	 */
	public var code:String = "";
	private var frozenCode:String;
	
	public function freeze():Void {
		frozenCode = code;
		code = "";
	}
	
	public function melt():Void {
		code += frozenCode;
		frozenCode = "";
	}	
	
	public function new(symbolTable:SymbolTable) {
		this.symbolTable = symbolTable;
	}
	
	/**
	 * 연산자 번호를 구한다.
	 * 
	 * @param	type
	 * @return
	 */
	public static function getOperatorNumber(type:Token.Type):Int {
		switch (type) {
		case Type.Addition, Type.AdditionAssignment:
			return 1;
		case Type.Subtraction, Type.SubtractionAssignment:
			return 2;
		case Type.Division, Type.DivisionAssignment:
			return 3;
		case Type.Multiplication, Type.MultiplicationAssignment:
			return 4;
		case Type.Modulo, Type.ModuloAssignment:
			return 5;
		case Type.BitwiseAnd, Type.BitwiseAndAssignment:
			return 6;
		case Type.BitwiseOr, Type.BitwiseOrAssignment:
			return 7;
		case Type.BitwiseXor, Type.BitwiseXorAssignment:
			return 8;
		case Type.BitwiseNot:
			return 9;
		case Type.BitwiseLeftShift, Type.BitwiseLeftShiftAssignment:
			return 10;
		case Type.BitwiseRightShift, Type.BitwiseRightShiftAssignment:
			return 11;
		case Type.EqualTo:
			return 12;
		case Type.NotEqualTo:
			return 13;
		case Type.GreaterThan:
			return 14;
		case Type.GreaterThanOrEqualTo:
			return 15;
		case Type.LessThan:
			return 16;
		case Type.LessThanOrEqualTo:
			return 17;
		case Type.LogicalAnd:
			return 18;
		case Type.LogicalOr:
			return 19;
		case Type.LogicalNot:
			return 20;
		case Type.Append, Type.AppendAssignment:
			return 21;
		case Type.CastToNumber:
			return 22;
		case Type.CastToString:
			return 23;
		case Type.RuntimeValueAccess:
			return 24;
		case Type.UnraryMinus:
			return 25;
		case Type.CharAt:
			return 26;
		default:
			return 0;
		}
	}
	
	/**
	 * 토큰열로 구성된 스택 어셈블리를 직렬화한다.
	 * 
	 * @param tokens
	 */
	public function writeLine(tokens:Array<Token>):Void {
		for ( i in 0...tokens.length) { 
			var token:Token = tokens[i];

			switch (token.type) {

			// 접두형 단항 연산자
			case Type.CastToNumber, Type.CastToString, Type.LogicalNot,
				 Type.BitwiseNot, Type.UnraryMinus:

				writeCode("POP 0");
				writeCode("OPR 1, " + getOperatorNumber(token.type) + ", &0");
				writeCode("PSH &1");
				
			// 값을 증감시킨 다음 푸쉬한다.
			case Type.PrefixDecrement, Type.PrefixIncrement:
				
				// 배열 인덱스 연산
				if (token.useAsArrayReference) {					
					writeCode("POP 0");
					writeCode("POP 1");
					writeCode("ESI 2, &1, &0");
					writeCode("OPR 2, " + (token.type == Token.Type.PrefixIncrement ? 1 : 2) + ", &2, @"
							+ symbolTable.getLiteral("1", LiteralSymbol.NUMBER).address);
					writeCode("EAD &1, &0, &2");
					if (!token.doNotPush)
						writeCode("PSH &2");
				} 
				
				else {
					writeCode("POP 0");
					writeCode("OPR 1, " + (token.type == Token.Type.PrefixIncrement ? 1 : 2) + ", @&0, @"
							+ symbolTable.getLiteral("1", LiteralSymbol.NUMBER).address);
					writeCode("NDW &0, &1");
					if (!token.doNotPush)
						writeCode("PSH @&0");
				}
				
			// 값을 푸쉬한 다음 증감시킨다.
			case Type.SuffixDecrement, Type.SuffixIncrement:
				
				// 배열 인덱스 연산
				if (token.useAsArrayReference) {
					writeCode("POP 0");
					writeCode("POP 1");
					writeCode("ESI 2, &1, &0");
					if (!token.doNotPush)
						writeCode("PSH &2");
					writeCode("OPR 2, " + (token.type == Token.Type.SuffixIncrement ? 1 : 2) + ", &2, @"
							+ symbolTable.getLiteral("1", LiteralSymbol.NUMBER).address);
					writeCode("EAD &1, &0, &2");			
				} 
				
				else {
					writeCode("POP 0");
					if (!token.doNotPush)
						writeCode("PSH @&0");
					writeCode("OPR 1, " + (token.type == Token.Type.SuffixIncrement ? 1 : 2) + ", @&0, @"
							+ symbolTable.getLiteral("1", LiteralSymbol.NUMBER).address);
					writeCode("NDW &0, &1");
				}
				
			// 이항 연산자
			case Type.Addition, Type.Subtraction, Type.Division,
				 Type.Multiplication, Type.Modulo, Type.BitwiseAnd,
				 Type.BitwiseOr, Type.BitwiseXor, Type.BitwiseLeftShift,
				 Type.BitwiseRightShift, Type.LogicalAnd, Type.LogicalOr,
				 Type.Append, Type.EqualTo, Type.NotEqualTo,
				 Type.GreaterThan, Type.GreaterThanOrEqualTo, Type.LessThan,
				 Type.LessThanOrEqualTo, Type.RuntimeValueAccess, Type.CharAt:	
					 
				writeCode("POP 0");
				writeCode("POP 1");
				writeCode("OPR 2, " + getOperatorNumber(token.type) + ", &1, &0");
				writeCode("PSH &2");
			
			// 이항 연산 후 대입 연산자
			case Type.AdditionAssignment, Type.SubtractionAssignment, Type.DivisionAssignment,
				 Type.MultiplicationAssignment, Type.ModuloAssignment, Type.BitwiseAndAssignment,
				 Type.BitwiseOrAssignment, Type.BitwiseXorAssignment, Type.BitwiseLeftShiftAssignment,
				 Type.BitwiseRightShiftAssignment, Type.AppendAssignment:
				
				// 배열 인덱스 연산	 
				if (token.useAsArrayReference) {	 
					writeCode("POP 0");
					writeCode("POP 1");
					writeCode("POP 2");
					writeCode("ESI 3, &2, &1");
					writeCode("OPR 3, " + getOperatorNumber(token.type) + ", &3, &0");
					writeCode("EAD &2, &1, &3");
				}
				
				// 일반 변수 연산
				else {
					
					writeCode("POP 0");
					writeCode("POP 1");
					writeCode("OPR 2, " + getOperatorNumber(token.type) + ", @&1, &0");
					
					if (token.type == Type.AppendAssignment)
						writeCode("SDW &1, &2");
					else
						writeCode("NDW &1, &2");
				}

			// 이항 대입 연산자
			case Type.Assignment:

				// 배열 인덱스 연산
				if (token.useAsArrayReference) {					
					writeCode("POP 0"); // 계산을 위한 값
					writeCode("POP 1"); // 배열 인덱스
					writeCode("POP 2"); // 실제 배열
					writeCode("EAD &2, &1, &0"); // 새로운 값 대입
				}
				
				else {
					
					writeCode("POP 0");
					writeCode("POP 1");

					switch (token.value) {
					// 실수형
					case "number", "bool": writeCode("NDW &1, &0");
					// 문자형
					case "string": writeCode("SDW &1, &0");						
					// 배열	
					case "array": writeCode("RDW &1, &0");						
					// 레퍼런스형
					default: writeCode("RDW &1, &0");
					}
				}

			// 배열 참조 연산자
			case Type.ArrayReference:

				// 배열의 차원수를 취득한다.
				var dimensions:Int = Std.parseInt(token.value);

				// 배열 어드레스를 pop한 후(0) 배열의 차원 수만큼 POP 한다.
				for(j in 0...(dimensions + 1))
					writeCode("POP " + j);

				/* ESI (indicator) register, (value) array, (value) index
				 * EAD (value) array, (value) index, (value) address
				 * 
				 * a[A][B] =
				 * 
				 * PUSH A
				 * PUSH B
				 * PUSH a
				 * POP 0 // a
				 * POP 1 // B
				 * POP 2 // A
				 * ESI 0, 0, 2
				 * ESI 0, 0, 1
				 */
				var j:Int = dimensions + 1;
				while(--j > 1)
					writeCode("ESI 0, &0, &" + j);
				
				// 배열 읽기/쓰기	
				if (token.useAsAddress) {
					writeCode("PSH &0"); // 실제 배열
					writeCode("PSH &1"); // 인덱스
					
				} else {
					
					writeCode("ESI 0, &0, &1");					
					// 결과를 메인 스택에 집어넣는다.
					writeCode("PSH &0");
				}
			
			// 파라미터 저장
			case Type.PushParameters:
				if (true) {
					
					var functn:FunctionSymbol = cast(token.getTag(), FunctionSymbol);
					
					if (functn.parameters != null) {
						for ( j in 0...functn.parameters.length) {
							
							var parameter:VariableSymbol = functn.parameters[j];								
							
							writeCode("PSH @" + parameter.address+", 1");	
							//writeCode("EXE print, @" + parameter.address);	
						}
					}
				}				
				
			// 함수 호출 / 어드레스 등의 역할
			case Type.ID:

				var symbol:Symbol = token.getTag();

				// 변수일 경우				
				if (Std.is(symbol, VariableSymbol)) {
					
					if (token.useAsAddress)
						writeCode("PSH " + symbol.address);
					else
						writeCode("PSH @" + symbol.address);					
				}

				// 함수일 경우
				else if (Std.is(symbol, FunctionSymbol)) {
					
					var functn:FunctionSymbol = cast(symbol, FunctionSymbol);

					// 네이티브 함수일 경우
					if (functn.isNative) {

						// 그냥 네이티브 어셈블리를 쓴다.
						writeCode(functn.nativeFunction.assembly);

					} else {

						/*
						 * 프로시져 호출의 토큰 구조는
						 * 
						 * ARG1, ARG2, ... ARGn, PROC_ID 로 되어 있다.
						 */
						
						// 인수를 뽑아 낸 후, 프로시져의 파라미터에 대응시킨다.
						if (functn.parameters != null) {
							for( j in 0...functn.parameters.length){

								// 인수 값을 뽑는다.
								writeCode("POP 0");							
								
								// 파라미터 어드레스를 취득한다. 인수를 거꾸로 취득하고 있으므로, 매개변수도 거꾸로
								// 취득한다.
								var parameter:VariableSymbol = functn.parameters[functn.parameters.length - 1 - j];
								
								// 인수가 실수형일 경우
								if (parameter.isNumber())
									writeCode("NDW " + parameter.address + ", &0");

								else if (parameter.isString())
									writeCode("SDW " + parameter.address + ", &0");

								else
									writeCode("RDW " + parameter.address + ", &0");
							}
						}

						// 현재 위치를 스택에 넣는다.
						writeCode("PSH $0, 1");

						// 함수 시작부로 점프한다.
						writeCode("JMP 0, %" + functn.functionEntry);						
						
						// 파라미터를 복구한다.						
						if (functn.parameters != null){
							for( j in 0...functn.parameters.length){

								// 인수 값을 뽑는다.
								writeCode("POP 0, 1");

								// 순서가 뒤바뀜
								var parameter:VariableSymbol = functn.parameters[functn.parameters.length - 1 - j];

								// 인수가 실수형일 경우
								if (parameter.isNumber())
									writeCode("NDW " + parameter.address + ", &0");

								else if (parameter.isString())
									writeCode("SDW " + parameter.address + ", &0");

								else
									writeCode("RDW " + parameter.address + ", &0");
								//writeCode("EXE print, &0");
							}
						}
					}
				}

			case Type.True, Type.False, Type.String, Type.Number:

				// 리터럴 심볼을 취득한다.
				var literal:LiteralSymbol = cast(token.getTag(), LiteralSymbol);

				// 리터럴의 값을 추가한다.
				writeCode("PSH @" + literal.address);
				
			case Type.Array:

				// 현재 토큰의 값이 인수의 갯수가 된다.
				var numberOfArguments:Int = Std.parseInt(token.value);

				// 인수 갯수 만큼 뽑아 온다.
				for ( j in 0...numberOfArguments)
					// 인수 어드레스를 뽑는다.
					writeCode("POP " + (numberOfArguments - j));

				// 동적 배열을 할당한다.
				writeCode("DAA 0");

				// 배열에 집어넣기 작업
				for ( j in 0...numberOfArguments) 
					writeCode("EAD @&0, "+j+", &" + (j + 1));

				// 배열을 리턴한다.
				writeCode("PSH @&0");

			case Type.Instance:

				// 앞 토큰은 인스턴스의 클래스이다.
				var targetClass:ClassSymbol = cast(tokens[i - 1].getTag(), ClassSymbol);
				
				// 인스턴스를 동적 할당한다.
				writeCode("DAA 0");

				// 오브젝트의 맴버 변수에 해당하는 데이터를 동적 할당한다.
				var assignedIndex:Int = 0;
				for ( j in 0...targetClass.members.length) {

					if (Std.is(targetClass.members[j], FunctionSymbol))
						continue;

					var member:VariableSymbol = cast(targetClass.members[j], VariableSymbol);

					// 초기값을 할당한다.
					if (member.type == "string") {
						writeCode("DSA 1");
						if (member.initialized)
							writeCode("SDW &1, @" + member.address);
					} else if (member.type == "number" || member.type == "bool") {
						writeCode("DNA 1");
						if (member.initialized)
							writeCode("NDW &1, @" + member.address);
					} else {
						writeCode("DAA 1");
						if (member.initialized)
							writeCode("RDW &1, @" + member.address);
					}

					// 인스턴스에 맴버를 추가한다.
					writeCode("EAD @&0, " + assignedIndex + ", @&1");
					assignedIndex++;
				}

				// 배열을 리턴한다.
				writeCode("PSH @&0");
				default:
			}
		}
	}

	/**
	 * 어셈블리 코드를 추가한다.
	 * 
	 * @param	code
	 */
	public function writeCode(code:String):Void {
		this.code += code + "\n";
	}

	
	/**
	 * 플래그를 심는다.
	 * 
	 * @param	number
	 */
	public function flag(number:Int):Void {
		writeCode("FLG %" + number);
	}
	
}