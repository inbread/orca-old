package elsa;

import elsa.debug.Debug;
import elsa.Lexer.Lextree;
import elsa.Parser.Instruction;
import elsa.Parser.ParsedPair;
import elsa.Parser.ParseOption;
import elsa.Parser.ScanOption;
import elsa.Symbol.Function;
import elsa.Symbol.Literal;
import elsa.Symbol.Variable;
import elsa.syntax.ArrayReferenceSyntax;
import elsa.syntax.ArraySyntax;
import elsa.syntax.CastingSyntax;
import elsa.syntax.ClassDeclarationSyntax;
import elsa.syntax.ElseSyntax;
import elsa.syntax.ForSyntax;
import elsa.syntax.FunctionCallSyntax;
import elsa.syntax.FunctionDeclarationSyntax;
import elsa.syntax.IfSyntax;
import elsa.syntax.ElseIfSyntax;
import elsa.syntax.InfixSyntax;
import elsa.syntax.InstanceCreationSyntax;
import elsa.syntax.MemberReferenceSyntax;
import elsa.syntax.PrefixSyntax;
import elsa.syntax.SuffixSyntax;
import elsa.syntax.VariableDeclarationSyntax;
import elsa.syntax.WhileSyntax;
import elsa.syntax.ContinueSyntax;
import elsa.syntax.BreakSyntax;
import elsa.syntax.ReturnSyntax;
import elsa.syntax.ParameterDeclarationSyntax;

/**
 * 구문 분석/재조립 파서
 * 
 * @author 김 현준
 */
class Parser {

	/**
	 * 어휘 분석기
	 */
	public var lexer:Lexer;
	
	/**
	 * 코드 최적화
	 */
	public var optimizer:Optimizer;
	
	/**
	 * 심볼 테이블
	 */
	public var symbolTable:SymbolTable;
	
	/**
	 * 어셈블리 코드 저장소
	 */
	private var assembly:Assembly;
	
	/**
	 * 플래그 카운터
	 */
	private var flagCount:Int = 0;
	
	private function assignFlag():Int {
		return flagCount ++;
	}
	
	public function new() { }
	
	public function compile(code:String):String {
		
		// 파싱 시 필요한 객체를 초기화한다.
		lexer = new Lexer();
		optimizer = new Optimizer();	
		symbolTable = new SymbolTable();		
		assembly = new Assembly(symbolTable);
		
		flagCount = 0;

		// 네이티브 라이브러리를 로드한다.
		NativeLibrary.load(symbolTable);
		
		// 어휘 트리를 취득한다.
		var lextree:Lextree = lexer.analyze(code);
		lexer.viewHierarchy(tree, 0);
		
		// 현재 스코프를 스캔한다. 현재 스코프에서는 오브젝트 정의와 프로시저 정의만을 스캔한다.
		scan(lextree, new ScanOption());
		parse(lextree, new ParseOption());

		assembly.freeze();

		// 리터럴을 어셈블리에 쓴다.
		for (Symbol.Literal literal : symbolTable.literal) {

			// 실수형 리터럴인 경우
			if (literal.type.equals(Symbol.Literal.NUMBER)) {
				assembly.writeCode("SNA @" + literal.address);

				// 리터럴 어드레스에 값을 할당한다.
				assembly.writeCode("NDW @" + literal.address + ", " + literal.value);
			}

			// 문자형 리터럴인 경우
			else if (literal.type.equals(Symbol.Literal.STRING)) {
				assembly.writeCode("SSA @" + literal.address);

				// 리터럴 어드레스에 값을 할당한다.
				assembly.writeCode("SDW @" + literal.address + ", " + literal.value);
			}

		}

		assembly.melt();
		assembly.code += "END";

		// 모든 파싱이 끝나면 어셈블리 코드를 최적화한다.
		assembly.code = optimizer.optimize(assembly.code);

		return assembly;
	}
	
	public function parseBlock(block:Lextree, option:ParseOption):Void {
		
		// 현재 스코프에서 생성된 변수와 프로시져를 저장한다. (맨 마지막에 심볼 테이블에서 삭제를 위함)
		var definedSymbols:Array<Symbol> = new Array<Symbol>();

		// 확장된 조건문 사용 여부
		var extendedConditional:Bool = false;
		var extendedConditionalExit:Int = 0; // 조건문의 탈출 플래그 (마지막 else나 elif 문의 끝)

		var i:Int = -1;
		
		// 라인 단위로 파싱한다.
		while ( ++i < block.branch.length) {
			
			var line:Lextree = block.branch[i];
			var lineNumber:Int = line.lineNumber;

			// 다른 제어문의 도움 없이 코드 블록이 단독으로 사용될 수 없다.
			if (line.hasBranch) {
				Debug.report("구문 오류", "예상치 못한 코드 블록입니다.", lineNumber);
				continue;
			}

			// 라인의 토큰열을 취득한다.
			var tokens:Array<Token> = line.lexData;

			if (tokens.length < 1)
				continue;

			// 현재 내려진 명령이 유효한지 확인한다.
			switch (tokens[0].type) {
				
			case CLASS, VARIABLE, ARRAY, FUNCTION:
				break;
				
			case IF, ELSE_IF, ELSE, FOR, WHILE:
				if (option.inStructure) {
					Debug.report("구문 오류", "구조체 정의에서 제어문을 사용할 수 없습니다.", lineNumber);
					continue;
				}
				break;
				
			case CONTINUE, BREAK:
				if (!option.inIterator) {
					Debug.report("구문 오류", "제어 명령은 반복문 내에서만 사용할 수 있습니다.", lineNumber);
					continue;
				}
				break;
				
			case RETURN:
				if (!option.inFunction) {
					Debug.report("구문 오류", "리턴 명령은 함수 정의 내에서만 사용할 수 있습니다.", lineNumber);
					continue;
				}
				break;
				
			default:
				if (option.inStructure) {
					Debug.report("구문 오류", "구조체 정의에서 연산 처리를 할 수 없습니다.", lineNumber);
					continue;
				}
			}
			
			// 변수 선언문
			if (VariableDeclarationSyntax.match(tokens)) {				
				
				var syntax:VariableDeclarationSyntax = VariableDeclarationSyntax.analyze(tokens, lineNumber);

				// 만약 구문 분석 중 오류가 발생했다면 다음 구문으로 건너 뛴다.
				if (syntax == null)
					continue;

				// 변수 타입이 유효한지 확인한다.
				if (!symbolTable.isValidClassID(syntax.variableType.value)) {
					Debug.report("타입 오류", "유효하지 않은 변수 타입입니다.", lineNumber);
					continue;
				}

				var variable:Symbol.Variable = null;

				// 구조체 정의인 경우 이미 스캔이 된 상태이므로 테이블에서 불러온다.
				if (option.inStructure) {
					variable = cast(symbolTable.findInLocal(syntax.variableName.value), Symbol.Variable);
				}

				// 구조체 정의가 아닌 경우 변수 심볼을 생성하고 테이블에 추가한다.
				else {

					// 변수 정의가 유효한지 확인한다.
					if (symbolTable.isValidVariableID(syntax.variableName.value)) {
						Debug.report("정의 중복 오류", "변수 정의가 중복되었습니다.", lineNumber);
						continue;
					}

					variable = new Symbol.Variable(syntax.variableName.value, syntax.variableType.value);
					symbolTable.add(variable);
				}

				// 토큰에 심볼을 태그한다.
				syntax.variableName.setTag(variable);				

				// 정의된 심볼 목록에 추가한다.
				definedSymbols.push(variable);

				// 어셈블리에 변수의 메모리 어드레스 할당 명령을 추가한다,
				if (variable.isNumber())
					assembly.writeAssembly("SNA @" + variable.address);

				else if (variable.isString())
					assembly.writeAssembly("SSA @" + variable.address);

				else					
					assembly.writeAssembly("SAA @" + variable.address);

				// 초기화 데이터가 존재할 경우
				if (syntax.initializer != null) {
					variable.initialized = true;

					// 초기화문을 파싱한 후 어셈블리에 쓴다.
					var parsedInitializer:ParsedPair = parse(syntax.initializer, lineNumber);

					if (parsedInitializer == null) continue;
					assembly.writeLine(parsedInitializer.data);
				}
			}
			
			
			else if (FunctionDeclarationSyntax.match(tokens)) {
				
				// 함수 구문을 분석한다.
				var syntax:FunctionDeclarationSyntax = FunctionDeclarationSyntax.analyze(tokens, lineNumber);

				// 만약 구문 분석 중 오류가 발생했다면 다음 구문으로 건너 뛴다.
				if (syntax == null)	continue;

				// 테이블에서 함수 심볼을 가져온다. (이미 스캐닝 과정에서 함수가 테이블에 등록되었으므로)
				var functn:Symbol.Function = cast(symbolTable.find(syntax.name.value), Symbol.Function);

				// 함수 토큰을 태그한다.
				syntax.functionName.setTag(functn);
				
				// 정의된 심볼 목록에 추가한다.
				definedSymbols.push(functn);

				// 다음 라인이 블록 형태인지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "함수 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				// 프로시져 시작 부분과 종결 부분을 나타내는 플래그를 생성한다.
				functn.functionEntry = assignFlag();
				functn.functionExit = assignFlag();

				// 프로시져가 임의로 실행되는 것을 막기 위해 프로시저의 끝 부분으로 점프한다.
				assembly.writeCode("JMP 0, %" + functn.exit);

				// 프로시져의 시작 부분을 알려주는 코드
				assembly.flag(functn.entry);

				// 프로시져 구현부를 파싱한다. 옵션: 함수
				var functionOption:ParseOption = option.copy();

				functionOption.inStructure = false;
				functionOption.insFunction = true;
				functionOption.inIterator = false;
				functionOption.parentFunction = functn;

				parseBlock(block.branch[++i], functionOption);

				/*
				 * 프로시져 호출 매커니즘은 다음과 같다.
				 * 
				 * 호출 스택에 기반하여 프로시져의 끝에서 마지막 스택 플래그로 이동.(pop)
				 */
				// 마지막 호출 위치를 가져온다.
				assembly.writeCode("POP 0");

				// 마지막 호출 위치로 이동한다. (이 명령은 함수가 void형이고, 리턴 명령을 결국 만나지 못했을 때 실행되게
				// 된다.)
				assembly.writeCode("JMP 0, &0");

				// 리턴형이 있는 함수에서 리턴 명령이 실행되지 않으면 0값을 출력한다.
				if (!functn.isVoid()) {
					assembly.writeCode("PSH 0");
				}

				// 프로시져의 끝 부분을 표시한다.
				assembly.flag(functn.exit);
			}
			
			
			else if (ClassDeclarationSyntax.match(tokens) {
				
				// 오브젝트 구문을 분석한다.
				var syntax:ClassDeclarationSyntax = ClassDeclarationSyntax.analyze(tokens, lineNumber);

				// 만약 구문 분석 중 오류가 발생했다면 다음 구문으로 건너 뛴다.
				if (syntax == null)
					continue;

				// 다음 라인이 블록 형태인지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "클래스의 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				// 클래스 내부의 클래스일 경우 구현부를 스캔한다.
				if (option.inStructure) {

					// 클래스 정의를 취득한다.
					var classs:Symbol.Class = cast(symbolTable.findInLocal(syntax.className.value), Symbol.Class);

					var innerScanOption:ScanOption = new ScanOption();
					innerScanOption.inStructure = true;
					innerScanOption.classSymbol = classs;

					scan(block.branch[i + 1], innerScanOption);
				}

				// 오브젝트 역시 스캔이 끝난 상태로, 하위 항목의 기본 선언 정보는 기록되어 있으나, 실제 명령은 파싱되지 않은
				// 상태이다. 하위 종속 항목들에 대해 파싱한다.
				var classOption:ParseOption = option.copy();
				classOption.inStructure = true;
				classOption.inIterator = false;
				classOption.inFunction = false;

				parseBlock(block.branch[++i], classOption);

				// 정의된 심볼 목록에 추가한다.
				definedSymbols.push(symbolTable.findInLocal(syntax.className.value));
			}
			
			
			else if (IfSyntax.match(tokens) {				
				
				var syntax:IfSyntax = IfSyntax.analyze(tokens, lineNumber);

				// 만약 IF문의 구문이 유효하지 않으면 다음으로 건너 뛴다.
				if (syntax == null)
					continue;

				// if문은 확장된 조건문의 시작이므로 초기화한다.				
				extendedConditional = false;

				// 뒤에 else if 나 else를 가지고 있으면 확장된 조건문을 사용한다.
				if (hasNextConditional(block, i))
					extendedConditional = true;
				else
					extendedConditional = false;
				
				extendedConditionalExit = assignFlag();

				// 조건문을 취득한 후 파싱한다.
				var parsedCondition:ParsedPair = parseLine(syntax.condition, lineNumber);

				// 조건문 결과 타입이 정수형이 아니라면 (True:1, False:0) 에러를 출력한다.
				if (parsedCondition.type != "number") {
					Debug.report("구문 오류", "참, 거짓 여부를 판별할 수 없는 조건식입니다.", lineNumber);
					continue;
				}

				// if문의 구현부가 존재하는지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "if문의 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				// 조건문 탈출 플래그
				var ifExit:Int = assignFlag();

				// 어셈블리에 조건식을 쓴다.
				assembly.writeLine(parsedCondition.data);
				assembly.writeCode("POP 0");

				// 조건이 거짓일 경우 구현부를 건너 뛴다.
				assembly.writeCode("JMP &0, %" + Std.string(ifExit));

				// 구현부를 파싱한다.
				var ifOption:ParseOption = option.copy();
				ifOption.inStructure = false;

				parseBlock(block.branch[++i], ifOption);
				assembly.flag(ifExit);		
			}
			
			
			else if (ElseIfSyntax.match(tokens) {
				
				// 확장된 조건문을 사용하지 않는 상태에서 else if문이 등장하면 에러를 출력한다
				if (extendedConditional) {
					Debug.report("구문 오류", "else-if문은 단독으로 쓰일 수 없습니다.", lineNumber);
					continue;
				}

				var syntax:ElseIfSyntax = ElseIfSyntax.analyze(tokens, lineNumber);

				// 만약 else if문의 구문이 유효하지 않으면 다음으로 건너 뛴다.
				if (syntax == null)
					continue;

				// 뒤에 else if 나 else를 가지고 있으면 확장된 조건문을 사용한다.
				if (hasNextConditional(block, i))
					extendedConditional = true;
				else
					extendedConditional = false;

				// 조건문을 취득한 후 파싱한다.
				var parsedCondition:ParsedPair = parseLine(syntax.condition, lineNumber);

				// 조건문 결과 타입이 정수형이 아니라면 (True:1, False:0) 에러를 출력한다.
				if (parsedCondition.type != "number") {
					Debug.report("구문 오류", "참, 거짓 여부를 판별할 수 없는 조건식입니다.", lineNumber);
					continue;
				}

				// if문의 구현부가 존재하는지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "if문의 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				// 조건문 탈출 플래그
				var elseIfExit:Int = 0;
				if (!extendedConditional)
					elseIfExit = extendedConditionalExit;
				else
					elseIfExit = flagCount++;

				// 어셈블리에 조건식을 쓴다.
				assembly.writeLine(parsedCondition.data);
				assembly.writeCode("POP 0");

				// 조건이 거짓일 경우 구현부를 건너 뛴다.
				assembly.writeCode("JMP &0, %" + Std.string(ifExit));

				// 구현부를 파싱한다.
				var ifOption:ParseOption = option.copy();
				ifOption.inStructure = false;

				parseBlock(block.branch[++i], ifOption);

				// 만약 참이라서 구현부가 실행되었을 경우, 조건 블록의 가장 끝으로 이동한다.
				if (extendedConditional) {
					assembly.writeCode("JMP 0, %" + Std.string(extendedConditionalExit));
					assembly.flag(ifExit);
				}
				
				// 만약 확장 조건문이 elseIf를 마지막으로 끝나는 경우라면
				else {
					assembly.flag(extendedConditionalExit);
				} 

			}
			
			else if (ElseSyntax.match(tokens) {
				var syntax:ElseSyntax = ElseSyntax.analyze(tokens, lineNumber);

				// 만약 else 문이 유효하지 않을 경우 다음으로 건너 뛴다.
				if (syntax == null) 
					continue;
				

				// 확장된 조건문을 사용하지 않는 상태에서 else문이 등장하면 에러를 출력한다
				if (extendedConditional) {
					Debug.report("구문 오류", "else문은 단독으로 쓰일 수 없습니다.", lineNumber);
					continue;
				}

				// 확장 조건문을 종료한다.
				extendedConditional = false;

				// else문의 구현부가 존재하는지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "else문의 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				// 구현부를 파싱한다. 만약 이터레이션 플래그가 있는 옵션일 경우 그대로 넘긴다.
				var elseOption:ParseOption = option.copy();
				elseOption.inStructure = false;

				parseBlock(block.branch.get[++i], elseOption);

				// 확장 조건문 종료 플래그를 쓴다.
				assembly.flag(extendedConditionalExit);
			}
			
			
			else if (ForSyntax.match(tokens)) {
				
				var syntax:ForSyntax = ForSyntax.ananlyze(tokens, lineNumber);

				// 만약 for문의 구문이 유효하지 않으면 다음으로 건너뛴다.
				if (syntax == null) 
					continue;
				

				// 증감 변수를 생성한다.
				var counter:Symbol.Variable = new Symbol.Variable(syntax.counter.value, "number");
				counter.initialized = true;

				// 증감 변수를 태그한다.
				syntax.counter.setTag(counter);

				// 테이블에 증감 변수를 등록한다.
				symbolTable.add(counter);
				definedSymbols.push(counter);

				// 초기값 파싱
				var parsedInitialValue:ParsedPair = parseLine(syntax.start, lineNumber);

				if (parsedInitialValue.type != "number") {
					Debug.report("타입 오류", "초기 값의 타입이 실수형이 아닙니다.", lineNumber);
					continue;
				}

				// for문의 기본 구성인 n -> k 에서 이는 기본적으로 while(n <= k)를 의미하므로 동치인 명령을
				// 생성한다.
				var condition:Array<Token> = TokenTools.merge([[syntax.counter, Token.find(Token.Type.LESS_THAN_OR_EQUAL_TO)], syntax.end]);
				var parsedCondition:ParsedPair = parse(condition, lineNumber);

				// 증감 조건문 파싱에 에러가 발생했다면 건너 뛴다.
				if (parsedCondition == null || parsedInitialValue == null)
					continue;

				// for문의 구현부가 존재하는지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "for문의 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				/*
				 * for의 어셈블리 구조는, 증감자 초기화(0) -> 귀환 플래그 -> 증감자 증감 -> 조건문(jump if
				 * false) -> 내용 ->귀환 플래그로 점프 -> 탈출 플래그 로 되어 있다.
				 */

				// 귀환/탈출 플래그 생성
				var forEntry:Int = assignFlag();
				var forExit:Int = assignFlag();

				// 증감자 초기화
				assembly.writeLine(parsedInitialValue.data);
				assembly.writeCode("POP 0");
				assembly.writeCode("SNA @" + Std.string(counter.address));
				assembly.writeCode("NDW @" + Std.string(counter.address) + ", &0");

				// 증감자의 값에서 -1을 해 준다.
				assembly.writeCode("OPR 1, 2, @" + Std.string(counter.address) + ", @"
						+ Std.string(symbolTable.getLiteral("1", Symbol.Literal.NUMBER).address));
				assembly.writeCode("NDW @" + Std.string(counter.address) + ", &1");

				// 귀환 플래그를 심는다.
				assembly.flag(forEntry);

				// 증감자 증감
				assembly.writeCode("OPR 1, 1, @" + Std.string(counter.address) + ", @"
						+ Std.string(symbolTable.getLiteral("1", Symbol.Literal.NUMBER).address));
				assembly.writeCode("NDW @" + Std.string(counter.address) + ", &1");

				// 조건문이 거짓이면 탈출 플래그로 이동
				assembly.writeLine(parsedCondition.data);
				assembly.writeCode("POP 0");
				assembly.writeCode("JMP &0, %" + Std.string(forExit));

				// for문의 구현부를 파싱한다. 이 때, 기존의 옵션은 뒤의 과정에서도 동일한 내용으로 사용되므로 새로운 옵션을
				// 생성한다.
				var forOption:ParseOption = option.copy();
				forOption.inStructure = false;
				forOption.inIterator = true;
				forOption.blockEntry = forEntry;
				forOption.blockExit = forExit;

				parseBlock(block.branch[++i], forOption);

				// 귀환 플래그로 점프
				assembly.writeCode("JMP 0, %" + Std.string(forEntry));

				// 탈출 플래그를 심는다.
				assembly.flag(forExit);
			}
			
			else if (WhileSyntax.match(tokens)) {
				
				var syntax:WhileSyntax = WhileSyntax.ananlyze(tokens, lineNumber);

				// 만약 while문의 정의가 올바르지 않다면 다음으로 건너 뛴다.
				if (syntax == null)
					continue;

				/*
				 * while의 어셈블리 구조는, 귀환 플래그 -> 조건문(jump if false) -> 내용 -> 귀환
				 * 플래그로 이동 -> 탈출 플래그로 되어 있다.
				 */

				// 조건문을 파싱한다.
				var parsedCondition:ParsedPair = parse(syntax.condition, lineNumber);

				// 파싱 과정에서 에러가 발생했다면 건너 뛴다.
				if (parsedCondition == null)
					continue;

				// while문의 구현부가 존재하는지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "while문의 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				// 귀환/탈출 플래그 생성
				var whileEntry:Int = assignFlag();
				var whileExit:Int = assignFlag();

				// 귀환 플래그를 심는다.
				assembly.flag(whileEntry);

				// 조건문을 체크하여 거짓일 경우 탈출 플래그로 이동한다.
				assembly.writeLine(parsedCondition.data);
				assembly.writeCode("POP 0");
				assembly.writeCode("JMP &0, %" + Std.string(whileExit));

				// while문의 구현부를 파싱한다.
				var whileOption:ParseOption = option.copy();
				whileOption.inStructure = false;
				whileOption.inIterator = true;
				whileOption.blockEntry = whileEntry;
				whileOption.blockExit = whileExit;

				parseBlock(block.branch[++i], whileOption);

				// 귀환 플래그로 점프한다.
				assembly.writeCode("JMP 0, %" + Std.string(whileEntry));

				// 탈출 플래그를 심는다.
				assembly.flag(whileExit);
			}
			
			else if (ContinueSyntax.match(tokens)) {
				
				// 귀환 플래그로 점프한다.
				assembly.writeCode("JMP 0, %" + Std.string(option.blockEntry));
			}
			
			else if (BreakSyntax.match(tokens)) {
				
				// 탈출 플래그로 점프한다.
				assembly.writeCode("JMP 0, %" + Std.string(option.blockExit));
			}
			
			else if (ReturnSyntax.match(tokens)) {
				
				var syntax:ReturnSyntax = ReturnSyntax.analyze(tokens, lineNumber);
				
				if (syntax == null)
					continue;
					
				if (!option.inFunction) {
					Debug.report("구문 오류", "return 명령은 함수 내에서만 사용할 수 있습니다.", lineNumber);
					continue;
				}
				
				// 만약 함수 타입이 Void일 경우 그냥 탈출 플래그로 이동한다.
				if (option.parentFunction.isVoid()) {

					// 반환값이 존재하면 에러를 출력한다.
					if (syntax.returnValue.length > 0) {
						Debug.report("구문 오류", "void형 함수는 값을 반환할 수 없습니다.", lineNumber);
						continue;
					}

					// 마지막 호출 지점을 가져온다.
					assembly.writeCode("POP 0");

					// 마지막 호출 지점으로 이동한다. (레지스터 값으로 점프 명령)
					assembly.writeCode("JMP 0, &0");
				}

				// 반환 타입이 있을 경우
				else {

					// 반환값이 없다면 에러를 출력한다.
					if (tokens.length < 1) {
						Debug.report("구문 오류", "return문이 값을 반환하지 않습니다.", lineNumber);
						continue;
					}

					// 마지막 호출 지점을 가져온다.
					assembly.writeCode("POP 0");

					// 마지막 호출 지점으로 이동한다. (레지스터 값으로 점프 명령)
					assembly.writeCode("JMP 0, &0");

					// 반환값을 파싱한다. 파싱된 결과는 스택에 저장된다.
					var parsedReturnValue:ParsedPair = parseLine(syntax.returnValue, lineNumber);

					if (parsedReturnValue == null)
						continue;

					if (parsedReturnValue.type != option.parentFunction.type) {
						Debug.report("구문 오류", "리턴된 데이터의 타입이 함수 리턴 타입과 일치하지 않습니다.", lineNumber);
						continue;
					}

					assembly.writeLine(parsedReturnValue.data);
				}
			}
			
			
			else {
				
				// 일반 대입문을 파싱한다.
				var parsedLine:ParsedPair = parseLine(tokens, lineNumber);
				if (parsedLine == null)
					continue;

				assembly.writeLine(parsedLine.data);
			}
			
		}
		
		// definition에 있던 심볼을 테이블에서 모두 제거한다.
		for (Symbol symbol : definedSymbols) {
			symbolTable.remove(symbol.id);
		}
	}
	
	
	/**
	 * 토큰열을 파싱한다.
	 * 
	 * @param	tokens
	 * @param	lineNumber
	 * @return
	 */
	public function parseLine(tokens:Array<Token>, lineNumber:Int):ParsedPair {
		
		// 토큰이 비었을 경우
		if (tokens.length < 1) {
			Debug.report("구문 오류", "계산식에 피연산자가 존재하지 않습니다.", lineNumber);
			return null;
		}

		// 의미 없는 껍데기가 있다면 벗긴다.
		tokens = TokenTools.pill(tokens);

		// 토큰열이 하나일 경우 (파싱 트리의 최하단에 도달했을 경우)
		if (tokens.length == 1) {

			// 변수일 경우 토큰의 유효성 검사를 한다.
			if (tokens[0].type == Token.Type.ID) {

				// 태그되지 않은 변수일 경우 유효성을 검증한 후 태그한다.
				if (!tokens[0].tagged) {
					if (!symbolTable.isValidVariableID(tokens[0].value)) {
						Debug.report("undefined 오류", tokens[0].value + "는 정의되지 않은 변수입니다.", lineNumber);
						return null;
					}
					// 토큰에 변수를 태그한다.
					tokens[0].setTag(symbolTable.findInLocal(tokens[0].value));
				}

				// 심볼 테이블에서 변수를 취득한다.
				var variable:Symbol.Variable = cast(tokens[0].getTag(), Symbol.Variable);

				return new ParsedPair(tokens, variable.type);
			}

			// 리터럴 값
			var literal:Symbol.Literal;

			switch (tokens[0].type) {

			// true/false 토큰은 각각 1/0으로 처리한다.
			case TRUE:
				literal = symbolTable.getLiteral("1", Symbol.Literal.NUMBER);
				break;
			case FALSE:
				literal = symbolTable.getLiteral("0", Symbol.Literal.NUMBER);
				break;
			case NUMBER:
				literal = symbolTable.getLiteral(tokens[0].value, Symbol.Literal.NUMBER);
				break;
			case STRING:
				literal = symbolTable.getLiteral(tokens[0].value, Symbol.Literal.STRING);
				break;
			default:
				Debug.report("구문 오류", "심볼의 타입을 찾을 수 없습니다.", lineNumber);
				return null;
			}

			// 토큰에 리터럴 태그하기
			tokens[0].setTag(literal);

			return ParsedPair(tokens, literal.type);
		}

		/**
		 * 함수 호출: F(X,Y,Z)
		 */
		if (FunctionCallSyntax.match(tokens)) {

			// 프로시저 호출 구문을 분석한다.
			var syntax:FunctionCallSyntax = FunctionCallSyntax.analyze(tokens, lineNumber);

			// 태그되지 않았을 경우, 함수가 유효한지 검사한 후, 태그한다.
			if (!syntax.functionName.tagged) {

				if (!symbolTable.isValidFunctionID(syntax.functionName.value)) {
					Debug.report("undefined 오류", "유효하지 않은 프로시져입니다.", lineNumber);
					return null;
				}

				// 토큰에 함수를 태그한다.
				syntax.functionName.setTag(symbolTable.findInLocal(syntax.procedure.value));
			}

			// 심볼 테이블에서 프로시저를 취득한다.
			var functn:Symbol.Function = cast(syntax.functionName.getTag(), Symbol.Function);

			// 매개 변수의 수 일치를 확인한다.
			if (functn.parameters.length != syntax.functionArguments.length) {
				Debug.report("구문 오류", "매개 변수의 수가 잘못되었습니다.", lineNumber);
				return null;
			}

			// 파라미터가 있을 경우
			if (syntax.functionArguments.length > 0) {

				var parsedArguments:Array<Array<Token>> = new Array<Array<Token>>();

				// 각각의 파라미터를 파싱한다.
				for( i in 0...syntax.functionArguments.length) {

					// 파라미터가 비었을 경우
					if (syntax.functionArguments[i].length < 1) {
						Debug.report("구문 오류", "파라미터가 비었습니다.", lineNumber);
						return null;
					}

					// 파라미터를 파싱한다.
					var parsedArgument:ParsedPair = parseLine(syntax.functionArguments[i], lineNumber);

					// 파라미터 파싱 과정에서 에러가 생겼다면 건너 뛴다.
					if (parsedArgument == null)
						return null;

					// 파라미터의 타입이 프로시져 정의에 명시된 매개변수 타입과 일치하는지 검사한다.
					if (functn.parameters[i].type != parsedArgument.type) {
						Debug.report("타입 오류", "매개 변수의 타입이 프로시져 정의에 명시된 매개변수 타입과 일치하지 않습니다.", lineNumber);
						return null;
					}

					// 파라미터를 쌓는다.
					parsedArguments[i] = parsedArgument.data;
				}

				// 쌓은 파라미터를 합쳐서 리턴한다.
				Token[] joinedArguments = TokenUtil.join(parsedArguments, 0, 1);
				joinedArguments[joinedArguments.length - 1] = syntax.procedure;

				return ParsedPair(joinedArguments, function.type);

			}

			// 매개 변수가 없을 경우
			else {
				return ParsedPair(new Token[] { tokens[0] }, function.type);
			}
		}

		/**
		 * 배열 생성 : [A, B, C, D, ... , ZZZ]
		 */
		else if (Array.match(tokens)) {

			Array syntax = Array.analyze(tokens, lineNumber);

			// 배열 리터럴 파싱 과정에 에러가 발생했다면 건너 뛴다.
			if (syntax == null)
				return null;

			Token[][] parsedArguments = new Token[syntax.arguments.length][];

			// 배열 리터럴의 각 원소를 파싱한 후 스택에 쌓는다.
			for (int i = 0; i < syntax.arguments.length; i++) {

				// 배열의 원소가 유효한지 체크한다.
				if (syntax.arguments[i].length < 1) {
					Debug.report("구문 오류", "배열에 불필요한 ','가 쓰였습니다.", lineNumber);
					return null;
				}

				// 배열의 원소를 파싱한다.
				Pair<Token[], String> parsedArgument = parse(syntax.arguments[i], lineNumber);

				// 원소에 에러가 있다면 건너 뛴다.
				if (parsedArgument == null)
					return null;

				parsedArguments[i] = parsedArgument.first;
			}

			/*
			 * 배열 리터럴의 토큰 구조는
			 * 
			 * A1, A2, A3, ... An, ARRAY_LITERAL(n)
			 */
			Token[] arrayLiteral = TokenUtil.join(parsedArguments, 0, 1);
			arrayLiteral[arrayLiteral.length - 1] = new Token(Token.Type.ARRAY,
					String.valueOf(parsedArguments.length));

			return ParsedPair(arrayLiteral, "array");

		}

		/**
		 * 객체 생성 : new A
		 */
		else if (Instance.match(tokens)) {

			// 객체 정보 취득
			Instance syntax = Instance.analyze(tokens, lineNumber);

			// 오브젝트 네임의 유효성 검증
			if (!symbolTable.isValidClassID(syntax.object.value)) {
				Debug.report("구문 오류", "유효하지 않은 오브젝트입니다.", lineNumber);
				return null;
			}

			// 오브젝트 심볼 취득
			Symbol.Class klass = (Symbol.Class) symbolTable.find(syntax.object.value);

			// 토큰에 오브젝트 태그
			syntax.object.setTag(klass);

			return ParsedPair(new Token[] { syntax.object, Token.find(Token.Type.INSTANCE) }, klass.id);

		}

		/**
		 * 인스턴스 참조 : A.B.C
		 */
		else if (InstanceReference.match(tokens)) {

			/*
			 * 도트 연산자는 우선순위가 가장 높기 때문에 파싱 트리의 최하단에 위치한 토큰열이 반환되게 된다. 따라서 도트 연산자로
			 * 걸러진 토큰은 무조건 A.B.C...Z 꼴이다. (단 A~Z는 변수 혹은 함수) 따라서 도트가 한번이라도 등장하면 그
			 * 뒤의 토큰열도 도트로 이어져 있다. -> 도트 처리는 일괄적으로 해도 됨
			 */

			// 참조 정보 취득
			InstanceReference syntax = InstanceReference.analyze(tokens, lineNumber);

			// 파싱된 참조열
			Token[][] parsedReferences = new Token[syntax.referneces.length][];

			// 컨텍스트
			Symbol.Class targetClass = null;

			// 리턴 타입
			String returnType = null;

			// 참조를 차례대로 파싱한다.
			for (int i = 0; i < syntax.referneces.length; i++) {
				Token[] reference = syntax.referneces[i];

				// 참조는 컨텍스트 내에서만 찾는다. (targetClass가 처음에는 null 이므로 첫 번째 실행에서는
				// 전역에서 심볼을 찾는다.)
				if (targetClass != null) {
					Symbol member = targetClass.findMember(reference[0].value);

					if (member == null) {
						Debug.report("undefined 오류", "속성을 찾을 수 없습니다.", lineNumber);
						return null;
					}

					// 토큰에 컨텍스트 내의 맴버를 태그한다.
					reference[0].setTag(member);
				}

				// 첫 번째 실행일 때
				else {

					// 유효하지 않다면 에러 출력
					if (!symbolTable.isValidVariableID(reference[0].value)
							&& !symbolTable.isValidFunctionID(reference[0].value)) {
						Debug.report("undefined 오류", "정의되지 않은 인스턴스입니다.", lineNumber);
						return null;
					}

				}

				// 참조를 파싱한다.
				Pair<Token[], String> parsedReference = parse(reference, lineNumber);

				// 참조 파싱 중 에러가 발생헀다면 건너 뛴다.
				if (parsedReference == null)
					return null;

				// targetClass 업데이트
				targetClass = (Symbol.Class) symbolTable.find(parsedReference.second);

				// 컨텍스트 로드 토큰
				Token loadContext = new Token(Token.Type.LOAD_CONTEXT);
				loadContext.setTag(targetClass);

				Token[] result;

				// 맨 마지막을 제외하고 컨텍스트 로드를 추가한다.
				if (i != syntax.referneces.length - 1)
					result = TokenUtil.join(parsedReference.first, new Token[] { loadContext });
				else
					result = parsedReference.first;

				// 리턴 타입을 업데이트한다.
				returnType = parsedReference.second;

				parsedReferences[i] = result;
			}

			// 파싱된 참조열을 리턴한다.
			return ParsedPair(TokenUtil.join(parsedReferences, 0, 0), returnType);
		}

		/**
		 * 배열 참조: a[1][2]
		 */
		else if (ArrayReference.match(tokens)) {

			/*
			 * 배열 인덱스 연산자는 우선순위가 가장 높고, 도트보다 뒤에 처리되므로 배열 인덱스 열기 문자 ('[')로 구분되는
			 * 토큰은 단일 변수의 n차 접근으로만 표시될 수 있다. 즉 이 프로시져에서 걸리는 토큰열은 모두 A[N]...[N]의
			 * 형태를 하고 있다. (단 A는 변수거나 프로시져)
			 * 
			 * A[1][2] -> GET 0, A 1 -> GET 1, 0, 2 -> PSH 1
			 */

			// 배열 참조 구문을 분석한다.
			ArrayReference syntax = ArrayReference.analyze(tokens, lineNumber);

			// 구문 오류가 있을 경우 리턴
			if (syntax == null)
				return null;

			// 배열이 태그되지 않은 경우 배열의 유효성을 검증한다.
			if (!syntax.array.tagged) {
				if (!symbolTable.isValidVariableID(syntax.array.value)) {
					Debug.report("undefined 오류", "정의되지 않은 배열입니다.", lineNumber);
					return null;
				}

				// 토큰에 배열 심볼을 태그한다.
				syntax.array.setTag(symbolTable.find(syntax.array.value));
			}

			Symbol.Variable array = (Symbol.Variable) syntax.array.getTag();

			// 변수가 배열이 아닐 경우
			if (!array.type.equals("array")) {

				// 변수가 문자열도 아니면, 에러
				if (!array.type.equals("string")) {
					Debugger.error(Debugger.TypeError, "인덱스 참조는 배열에서만 가능합니다.", lineNumber);
					return null;
				}

				// 문자열 인덱스 참조 명령을 처리한다.
				if (syntax.references.length != 1) {
					Debugger.error(Debugger.TypeError, "문자열을 n차원 배열처럼 취급할 수 없습니다.", lineNumber);
					return null;
				}

				// index A CharAt 의 순서로 배열한다.
				Pair<Token[], String> parsedIndex = parse(syntax.references[0], lineNumber);

				// 인덱스 파싱 중 에러가 발생했다면 건너 뛴다.
				if (parsedIndex == null)
					return null;

				// 인덱스가 정수가 아닐 경우
				if (!parsedIndex.second.equals("number")) {
					Debugger.error(Debugger.TypeError, "문자열의 인덱스가 정수가 아닙니다.", lineNumber);
					return null;
				}

				// 결과를 리턴한다.
				return ParsedPair(TokenUtil.join(new Token[] { syntax.array }, parsedIndex.first, new Token[] { Token
						.find(Token.Type.CHAR_AT) }), "string");
			}

			// 파싱된 인덱스들
			Token[][] parsedReferences = new Token[syntax.references.length][];

			// 가장 높은 인덱스부터 차례로 파싱한다.
			for (int i = 0; i < syntax.references.length; i++) {

				Token[] reference = syntax.references[i];

				Pair<Token[], String> parsedReference = parse(reference, lineNumber);

				if (parsedReference == null)
					continue;

				// 인덱스가 정수가 아닐 경우
				if (!parsedReference.second.equals("number")) {
					Debugger.error(Debugger.TypeError, "배열의 인덱스가 정수가 아닙니다.", lineNumber);
					continue;
				}

				// 할당
				parsedReferences[i] = parsedReference.first;
			}

			// A[a][b][c] 를 a b c A Array_reference(3) 로 배열한다.

			Token[] result = TokenUtil.join(parsedReferences, 0, 2);
			result[result.length - 1] = new Token(Token.Type.ARRAY_REFERENCE,
					String.valueOf(parsedReferences.length));
			result[result.length - 2] = syntax.array;

			// 리턴 타입은 어떤 타입이라도 될 수 있다.
			return ParsedPair(result, "*");

		}

		/**
		 * 캐스팅: stuff as number
		 */
		else if (Casting.match(tokens)) {

			Casting syntax = Casting.analyze(tokens, lineNumber);

			if (syntax == null)
				return null;

			// 캐스팅 대상을 파싱한 후 끝에 캐스팅 명령을 추가한다.
			Pair<Token[], String> parsedTarget = parse(syntax.target, lineNumber);

			if (parsedTarget == null)
				return null;

			// 문자형으로 캐스팅
			if (syntax.castingType.equals("string")) {

				// 아직은 숫자 -> 문자만 가능하다.
				if (!parsedTarget.second.equals("number")) {
					Debugger.error(Debugger.TypeError, "실수형이 아닌 타입을 문자형으로 캐스팅할 수 없습니다.", lineNumber);
					return null;
				}

				// 캐스팅된 문자열을 출력
				return ParsedPair(TokenUtil.join(parsedTarget.first, new Token[] { Token
						.find(Token.Type.CAST_TO_STRING) }), "string");

			}

			// 실수형으로 캐스팅
			else if (syntax.castingType.equals("number")) {

				// 아직은 문자 -> 숫자만 가능하다.
				if (!parsedTarget.second.equals("string")) {
					Debugger.error(Debugger.TypeError, "문자형이 아닌 타입을 실수형으로 캐스팅할 수 없습니다.", lineNumber);
					return null;
				}

				// 캐스팅된 문자열을 출력
				return ParsedPair(TokenUtil.join(parsedTarget.first, new Token[] { Token
						.find(Token.Type.CAST_TO_NUMBER) }), "number");
			}

			// 그 외의 경우
			else {

				// 캐스팅 타입이 적절한지 체크한다.
				if (!symbolTable.isValidClassID(syntax.castingType)) {
					Debug.report("undefined 오류", "올바르지 않은 타입입니다.", lineNumber);
					return null;
				}

				// 표면적으로만 캐스팅한다. -> [경고] 실질적인 형 검사가 되지 않기 때문에 VM이 죽을 수도 있다.
				return ParsedPair(parsedTarget.first, syntax.castingType);
			}

		}

		/**
		 * 접두형 단항 연산자: !(true) , ++a
		 */
		else if (Prefix.match(tokens)) {

			Prefix syntax = Prefix.analyze(tokens, lineNumber);

			if (syntax == null)
				return null;

			// 뒤 항은 단항 ID만 가능하다.
			if (syntax.operator.type == Token.Type.PREFIX_DECREMENT
					|| syntax.operator.type == Token.Type.PREFIX_INCREMENT) {

				// 단항 ID가 아닐 경우
				if (syntax.operand.length != 1 || syntax.operand[0].type != Token.Type.ID) {
					Debugger.error(Debugger.TypeError, "증감 연산자 사용이 잘못되었습니다.", lineNumber);
					return null;
				}
			}

			// 피연산자를 파싱한다.
			Pair<Token[], String> parsed = parse(syntax.operand, lineNumber);

			if (parsed == null)
				return null;

			// 접두형 연산자의 경우 숫자만 올 수 있다.
			if (!(parsed.second.equals("number") || parsed.second.equals("*"))) {
				Debugger.error(Debugger.TypeError, "접두형 연산자 뒤에는 실수형 데이터만 올 수 있습니다.", lineNumber);
				return null;
			}

			// 결과를 리턴한다.
			return ParsedPair(TokenUtil.join(parsed.first, new Token[] { syntax.operator }), parsed.second);

		}

		/**
		 * 접미형 단항 연산자: a++
		 */
		else if (Suffix.match(tokens)) {

			Suffix syntax = Suffix.analyze(tokens, lineNumber);

			if (syntax == null)
				return null;

			// 단항 ID가 아닐 경우
			if (syntax.operand.length != 1 || syntax.operand[0].type != Token.Type.ID) {
				Debugger.error(Debugger.TypeError, "증감 연산자 사용이 잘못되었습니다.", lineNumber);
				return null;
			}

			// 피연산자를 파싱한다.
			Pair<Token[], String> parsed = parse(syntax.operand, lineNumber);

			if (parsed == null)
				return null;

			// 접두형 연산자의 경우 숫자만 올 수 있다.
			if (!(parsed.second.equals("number") || parsed.second.equals("*"))) {
				Debugger.error(Debugger.TypeError, "접미형 연산자 앞에는 실수형 데이터만 올 수 있습니다.", lineNumber);
				return null;
			}

			// 결과를 리턴한다.
			return ParsedPair(TokenUtil.join(parsed.first, new Token[] { syntax.operator }), parsed.second);

		}

		/**
		 * 이항 연산자: a+b
		 */
		else if (Infix.match(tokens)) {

			Infix syntax = Infix.analyze(tokens, lineNumber);

			// 양 항을 모두 파싱한다.
			Pair<Token[], String> left = parse(syntax.left, lineNumber);
			Pair<Token[], String> right = parse(syntax.right, lineNumber);

			if (right == null || right == null)
				return null;

			// 와일드카드 처리, 와일드카드가 양 변에 한 쪽이라도 있으면
			if (left.second.equals("*") || right.second.equals("*")) {

				// 와일드카드가 없는 쪽으로 통일한다.
				if (!left.second.equals("*"))
					right.second = left.second;

				else if (!right.second.equals("*"))
					left.second = right.second;

				// 모두 와일드카드라면
				else {
					Debugger.error(Debugger.TypeError, "캐스팅되지 않아 타입을 알 수 없습니다.", lineNumber);
					return null;
				}
			}

			// 형 체크 프로세스: 두 항 타입이 같을 경우
			if (left.second.equals(right.second)) {

				// 만약 문자열에 대한 이항 연산이라면, 대입/더하기만 허용한다.
				if (left.second.equals("string")) {

					// 산술 연산자를 문자열 연산자로 수정한다.
					switch (syntax.operator.type) {
					case ADDITION_ASSIGNMENT:
						syntax.operator = Token.find(Token.Type.APPEND_ASSIGNMENT);
						break;
					case ADDITION:
						syntax.operator = Token.find(Token.Type.APPEND);
						break;

					// 문자열 - 문자열 대입이면 SDW명령을 활성화시킨다.
					case ASSIGNMENT:
						syntax.operator.value = "string";
					case EQUAL_TO:
					case NOT_EQUAL_TO:
						break;
					default:
						Debug.report("구문 오류", "이 연산자로 문자열 연산을 수행할 수 없습니다.", lineNumber);
						return null;
					}

				}

				// 숫자에 대한 이항 연산일 경우
				else if (left.second.equals("number")) {

					switch (syntax.operator.type) {
					// 실수형 - 실수형 대입이면 NDW명령을 활성화시킨다.
					case ASSIGNMENT:
						syntax.operator.value = "number";
						break;
					default:
						break;
					}

				}

				// 그 외의 배열이나 인스턴스의 경우
				else {
					switch (syntax.operator.type) {
					// 인스턴스 - 인스턴스 대입이면 NDW명령을 활성화시킨다.
					case ASSIGNMENT:
						syntax.operator.value = "instance";
						break;
					default:
						Debug.report("구문 오류", "대입 명령을 제외한 이항 연산자는 문자/숫자 이외의 처리를 할 수 없습니다.", lineNumber);
						return null;
					}
				}

			}

			// 형 체크 프로세스: 두 항의 타입이 다를 경우
			else {

				// 자동 캐스팅을 시도한다.
				switch (syntax.operator.type) {
				case ADDITION:

					// 문자 + 숫자
					if (left.second.equals("string") && right.second.equals("number")) {

						right.first = TokenUtil.join(right.first, new Token[] { Token
								.find(Token.Type.CAST_TO_STRING) });
						right.second = "string";

						// 연산자를 APPEND로 수정한다.
						syntax.operator = Token.find(Token.Type.APPEND);

					}

					// 숫자 + 문자
					else if (right.second.equals("string") && left.second.equals("number")) {

						left.first = TokenUtil.join(left.first, new Token[] { Token
								.find(Token.Type.CAST_TO_STRING) });
						left.second = "string";

						// 연산자를 APPEND로 수정한다.
						syntax.operator = Token.find(Token.Type.APPEND);

					}

					else {
						Debug.report("구문 오류", "다른 두 타입 간 연산을 실행할 수 없습니다.", lineNumber);
						return null;
					}

					break;
				default:
					Debug.report("구문 오류", "다른 두 타입 간 연산을 실행할 수 없습니다.", lineNumber);
					return null;
				}
			}

			// 형 체크가 끝나면 좌, 우 변을 잇고 리턴한다.
			Token[] result = TokenUtil
					.join(left.first, right.first, new Token[] { syntax.operator });
			return ParsedPair(result, right.second);

		}

		Debug.report("구문 오류", "연산자가 없는 식입니다.", lineNumber);
		return null;
	}
	
	
	/**
	 * 스코프 내의 프로시져와 오브젝트 정의를 읽어서 테이블에 기록한다.
	 * 
	 * @param	block
	 * @param	scanOption
	 */
	public function scan(block:Lextree, option:ScanOption):Void {
		
		// 구조체 스캔일 경우 맴버변수와 프로시져를 저장할 공간 생성
		var members:Array<Symbol> = null;

		if (option.inStructure) {
			members = new Array<Symbol>();
		}
	
		var i:Int = -1;
		while (++i < block.branch.length) {

			var line:Lextree = block.branch[i];
			var lineNumber:Int = line.lineNumber;

			// 만약 유닛에 가지가 있다면 넘어감
			if (line.hasBranch)
				continue;
				
			var tokens:Array<Token> = line.data;
			
			if (tokens.length < 1)
				continue;
			
			if (VariableDeclarationSyntax.match(tokens) {
				
				// 변수(맴버 변수)는 구조체에서만 스캔한다.
				if (!option.inStructure)
					continue;

				// 스캔시에는 에러를 표시하지 않는다. (파싱 단계에서 표시)
				Debug.supressError(true);

				var syntax:VariableDeclarationSyntax = VariableDeclarationSyntax.analyze(tokens, lineNumber);

				Debug.supressError(false);

				if (syntax == null)
					continue;

				// 변수 심볼을 생성한다.
				var variable:Symbol.Variable = new Symbol.Variable(syntax.variableName.value, syntax.variableType.value);

				// 이미 사용되고 있는 변수인지 체크
				if (symbolTable.isValidVariableID(variable.id)) {
					Debug.report("정의 중복 오류", "변수 정의가 충돌합니다.", lineNumber);
					continue;
				}

				// 심볼 테이블에 추가한다.
				symbolTable.add(variable);
				members.push(variable);
				
			}
			
			else if (FunctionDeclarationSyntax.match(tokens) {
				
				// 올바르지 않은 선언문일 경우 건너 뛴다.
				var syntax:FunctionDeclarationSyntax = FunctionDeclarationSyntax.analyze(tokens, lineNumber);

				// 스캔시에는 에러를 표시하지 않는다. (파싱 단계에서 표시)
				Debug.supressError(true);

				// 올바르지 않은 프로시저일 경우 건너 뛴다
				if (syntax == null)
					continue;

				Debug.supressError(false);
				
				var parameters:Array<Symbol.Variable> = new Array<Symbol.Variable>();

				// 매개 변수 정의가 존재하면
				if (syntax.parameters != null) {

					// 매개변수 각각의 유효성을 검증하고 심볼 형태로 가공한다.
					for ( k in 0...syntax.parameters.length) {
						
						if (!ParameterDeclarationSyntax.match(syntax.parameters[k])){
							Debug.report("구문 오류", "파라미터 정의가 올바르지 않습니다.", lineNumber);
							continue;
						}
						// 매개 변수의 구문을 분석한다.
						var parameterSyntax:ParameterDeclarationSyntax = ParameterDeclarationSyntax.analyze(syntax.parameters[k], lineNumber);

						// 매개 변수 선언문에 구문 오류가 있을 경우 건너 뛴다.
						if (parameterSyntax == null)
							continue;

						// 매개 변수 이름의 유효성을 검증한다.
						if (symbolTable.isValidVariableID(syntax.parameterName.value)) {
							Debug.report("정의 중복 오류", "변수 정의가 충돌합니다.", lineNumber);
							continue;
						}

						// 매개 변수 타입의 유효성을 검증한다.
						if (!symbolTable.isValidClassID(syntax.parameterType.value)) {
							Debug.report("정의 중복 오류", "매개 변수 타입이 유효하지 않습니다.", lineNumber);
							continue;
						}

						// 매개 변수 심볼을 생성한다
						var parameter:Symbol.Variable = new Symbol.Variable(syntax.parameterName.value, syntax.parameterType.value);

						parameterSyntax.parameterName.setTag(parameter);

						// 심볼 테이블에 추가한다.
						symbolTable.add(argument);
						parameters[k] = parameter;
					}
				}
				
				var functn:Symbol.Function = new Symbol.Function(syntax.functionName.value, syntax.returnType.value, parameters);

				// 프로시져를 심볼 테이블에 추가한다.
				symbolTable.add(functn);

				// 구조체 스캔일 경우 맴버 프로시져에도 추가한다.
				if (scanOption.structure)
					members.push(functn);				
			}
			
			else if (ClassDeclarationSyntax.match(tokens) {
				
				// 오브젝트 선언 구문을 분석한다.
				var syntax:ClassDeclarationSyntax = ClassDeclarationSyntax.analyze(tokens, lineNumber);

				// 오브젝트 선언 구문에 에러가 있을 경우 건너 뛴다.
				if (syntax == null)
					continue;

				// 오브젝트 이름의 유효성을 검증한다.
				if (symbolTable.isValidClassID(syntax.className.value)) {
					Debug.report("구문 오류", "오브젝트 정의가 중복되었습니다.", lineNumber);
					continue;
				}

				// 오브젝트 구현부가 존재하는지 확인한다.
				if (!hasNextBlock(block, i)) {
					Debug.report("구문 오류", "구조체의 구현부가 존재하지 않습니다.", lineNumber);
					continue;
				}

				// 오브젝트를 심볼 테이블에 추가한다.
				var classs:Symbol.Class = new Symbol.Class(syntax.className.value);

				symbolTable.add(classs);

				// 클래스 내부의 클래스는 지금 스캔하지 않는다.
				if (option.inStructure)
					continue;

				// 오브젝트의 하위 항목을 스캔한다.
				var objectOption:ScanOption = option.copy();
				objectOption.inStructure = true;
				objectOption.parentClass = classs;

				scan(block.branch[++i], objectOption);
			}
		}

		// 만약 구조체 스캔일 경우 맴버 변수와 프로시져 정의를 오브젝트 심볼에 쓴다.
		if (option.inStructure) {
			option.parentClass.members = members;
		}
	}	
	
}


/**
 * 파싱된 페어
 */
class ParsedPair {
	
	public var data:Array<Token>;
	public var type:String;
	
	public function new(data:Array<Token>, type:String) {
		this.data = data;
		this.type = type;
	}
}

/**
 * 파싱 옵션 클래스
 */
class ParseOption {
	
	/**
	 * 파싱 옵션
	 */
	public var inStructure:Bool = false;
	public var inFunction:Bool = false;
	public var inIterator:Bool = false;
	
	/**
	 * 블록의 시작과 끝 옵션
	 */
	public var blockEntry:Int = 0;
	public var blockExit:Int = 0;
	
	/**
	 * 함수 내부일 경우의 함수 참조
	 */
	public var parentFunction:Symbol.Function;
	
	/**
	 * 파싱 옵션 복사
	 * 
	 * @return
	 */
	public function copy():ParseOption {
		
		var option:ParseOption = new ParseOption();
		
		option.inStructure = inStructure;
		option.inFunction = inFunction;
		option.inIterator = inIterator;
		option.blockEntry = blockEntry;
		option.blockExit = blockExit;
		option.parentFunction = parentFunction;
		
		return option;
	}
	
}

/**
 * 스캔 옵션 클래스
 */
class ScanOption {
	
	/**
	 * 스캔 옵션
	 */
	public var inStructure:Bool = false;
	
	/**
	 * 함수 내부일 경우의 함수 참조
	 */
	public var parentClass:Symbol.Class;
	
	/**
	 * 스캔 옵션 복사
	 * 
	 * @return
	 */
	public function copy():ScanOption {
		
		var option:ScanOption = new ScanOption();
		
		option.inStructure = inStructure;
		option.parentClass = parentClass;
		
		return option;
	}
}