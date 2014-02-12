package elsa;
import elsa.Lexer.Lextree;
import elsa.debug.Debug;

/**
 * 어휘 분석 클래스
 * 
 * 코드를 분석하여 어휘 계층 트리를 생성한다.
 * 
 * @author 김 현준
 */
class Lexer {

	/**
	 * 어휘 분석 중인 라인 넘버
	 */
	private var processingLine:Int = 1;
	
	public function new() {
		
		// 토큰 정의가 비었다면 예약 어휘를 추가한다.
		if (Token.definitions.length < 1)
			defineTokens();
	}
	
	public function analyze(code:String):Lextree {		
		processingLine = 1;
		
		// 어휘 트리를 생성한다.
		var tree:Lextree = new Lextree(true, processingLine);
		
		// 문자열 처리 상태 변수를 초기화한다.
		var isString:Bool = false;
		var buffer:String = "";		
		
		var i:Int = -1;
		
		while(i <= code.length){			
			i ++;
			
			var char:String = code.charAt(i);
			
			// 줄바꿈 문자일 경우 줄 번호를 하나 증가시킨다.
			if (char == "\n")
				processingLine ++;
				
			// 문자열의 시작과 종결 부분을 감지하여 상태를 업데이트한다.
			if (char == "\"") {
				isString = !isString;
				buffer += char;
				continue;
			}

			// 모든 문자열 정보는 버퍼에 저장한다.
			if (isString) {
				buffer += char;
				continue;
			}
			
			// 주석을 제거한다.
			if (char == "/" && i + 1 < code.length) {
				var j:Int = 2;
				
				// 단일 행 주석일 경우
				if (code.charAt(i + 1) == "/") {

					// 문장의 끝(줄바꿈 문자)를 만날 때까지 넘긴다.
					while (i + j <= code.length) {
						if (code.charAt(i + (j++)) == "\n")
							break;
					}
					i += j - 1;
					processingLine++;
					continue;
				}
				
				// 여러 행 주석일 경우
				else if (code.charAt(i + 1) == "*") {

					// 종결 문자열 시퀸스('*/')를 만날 때까지 넘긴다.
					while (i + j < code.length) {
						if (code.charAt(i + j) == "\n")
							processingLine++;

						if (code.charAt(i + (j++)) == "*")
							if (code.charAt(i + (j++)) == "/")
								break;
					}
					i += j - 1;
					continue;
				}
			}
			
			// 세미콜론을 찾으면 진행 상황을 스택에 저장한다.
			if (char == ";") {

				// 진행 상황을 스택에 저장한다.
				if (buffer.length > 0){
					var lextree:Lextree = new Lextree(false, processingLine);
					lextree.lexData = tokenize(buffer);
					tree.branch.push(lextree);
				}

				// 버퍼를 초기화한다.
				buffer = "";
			}
			
			// 중괄호 열기 문자('{')를 찾으면 괄호로 묶인 그룹을 재귀적으로 처리하여 저장한다.
			else if (char == "{") {
		
				// 중괄호 앞의 데이터를 저장한다.
				if (buffer.length > 0){
					var lextree:Lextree = new Lextree(false, processingLine);
					lextree.lexData = tokenize(buffer);
					tree.branch.push(lextree);
				}
				
				// 괄호의 끝을 찾는다.
				var j:Int = 1;
				var depth:Int = 0;
				
				while (i + j <= code.length) {
					var char:String = code.charAt(i + (j++));
					if (char == "{")
						depth++;
					else if (char == "}")
						depth--;
					else if (char == "\n")
						processingLine++;
					if (depth < 0)
						break;
				}

				// 괄호의 전체 내용에 대해 구문 분석을 수행한 후, 유닛에 추가한다. (시작, 끝 괄호 제외)
				var block:Lextree = analyze(code.substring(i + 1, i + j - 1));				
				tree.branch.push(block);

				// 다음 과정을 준비한다.
				buffer = "";
				i += j;
			}
			
			// 처리하지 않는 문자일 경우 버퍼에 쓴다.
			else {
				buffer += char;
			}	
		}
		
		// 맨 뒤의 데이터도 쓴다.
		if (buffer.length > 0){
			var lextree:Lextree = new Lextree(false, processingLine);
			lextree.lexData = tokenize(buffer);
			tree.branch.push(lextree);
		}

		// 분석 결과를 리턴한다.
		return tree;
	}
	
	/**
	 * 정의된 토큰 정보를 바탕으로 문자열을 토큰화한다.
	 * 
	 * @param	code
	 * @return
	 */
	public function tokenize(code:String):Array<Token> {
		
		var tokens:Array<Token> = new Array<Token>();
		var buffer:String = "";

		var isString:Bool = false;
		var isNumber:Bool = false;
		var isFloat:Bool = false;

		var i:Int = -1;
		
		while (i < code.length) { 
			i ++;
			
			var char:String = code.charAt(i);

			// 문자열 처리
			if (char == "\"") {
				isString = !isString;

				// 문자열이 시작되었을때 기존의 버퍼를 저장한다.
				if (isString){
					if (buffer.length > 0)
						tokens.push(Token.findByValue(buffer, true));
				}
				
				// 문자열이 종결되었을 때 문자열 토큰 추가
				if (!isString)
					tokens.push(new Token(Token.Type.STRING, buffer));

				// 버퍼 초기화
				buffer = "";
				continue;
			}

			if (isString) {
				buffer += char;
				continue;
			}

			// 만약 숫자이고, 버퍼의 처음이라면 숫자 리터럴 처리를 시작한다.
			if (char.charCodeAt(0) >= "0".charCodeAt(0) && char.charCodeAt(0) <= "9".charCodeAt(0)) {
				if (buffer.length < 1)
					isNumber = true;
					
				if (isNumber) {
					buffer += char;
					continue;
				}
			}

			// 만약 숫자 리터럴 처리 중 '.'이 들어온다면 소수점 처리를 해 준다.
			if (isNumber && char == ".") {
				if (isFloat) 
					Debug.report("구문 오류", "소수점 표현이 잘못되었습니다.", processingLine);
				
				isFloat = true;
				buffer += char;
				continue;
			}

			// 만약 그 외의 문자가 온다면 숫자 리터럴을 종료한다.
			if (isNumber) {

				tokens.push(new Token(Token.Type.NUMBER, buffer));

				// 버퍼 초기화
				buffer = "";
				isNumber = false;
				isFloat = false;
			}

			// 공백 문자가 나오면 토큰을 분리한다.
			if (char == " " || char.charCodeAt(0) == 10 || char.charCodeAt(0) == 13) {
	
				var token:Token = Token.findByValue(StringTools.trim(buffer), true);
				
				if (buffer.length > 0 && token != null)
					tokens.push(token);

				// 버퍼 초기화
				buffer = "";
				continue;
			}
			
			// 토큰 분리 문자의 존재 여부를 검사한다.
			else if (i < code.length) {

				// 토큰을 찾는다.
				var result:Token = Token.findByValue(code.substring(i, (i + 2 < code.length ? i + 3
						: (i + 1 < code.length ? i + 2 : i + 1))), false);

				// 만약 토큰이 존재한다면,
				if (result != null) {

					// 토큰을 이루는 문자만큼 건너 뛴다.
					i += result.value.length - 1;

					// 버퍼를 쓴다
					
					var token:Token = Token.findByValue(StringTools.trim(buffer), true);
					if (buffer.length > 0 && token != null) 
						tokens.push(token);
					

					var previousToken:Token = null;
					var previousTarget:Bool = false;

					if (tokens.length > 0)
						previousToken = tokens[tokens.length - 1];
					else 
						previousTarget = false;
					
					
					// 더하기 연산자의 경우 앞에 더할 대상이 존재
					if (tokens.length > 0
							&& (previousToken.type == Token.Type.ID
							|| previousToken.type == Token.Type.NUMBER
							|| previousToken.type == Token.Type.STRING
							|| previousToken.type == Token.Type.SHELL_CLOSE)) {
						previousTarget = true;
					}

					// 연산자 수정
					if (result.type == Token.Type.ADDITION && !previousTarget)
						result = Token.findByType(Token.Type.UNRARY_PLUS);
					else if (result.type == Token.Type.UNRARY_PLUS && previousTarget)
						result = Token.findByType(Token.Type.ADDITION);
					else if (result.type == Token.Type.SUBTRACTION && !previousTarget)
						result = Token.findByType(Token.Type.UNRARY_MINUS);
					else if (result.type == Token.Type.UNRARY_MINUS && previousTarget)
						result = Token.findByType(Token.Type.SUBTRACTION);
					else if (result.type == Token.Type.SUFFIX_INCREMENT && !previousTarget)
						result = Token.findByType(Token.Type.PREFIX_INCREMENT);
					else if (result.type == Token.Type.PREFIX_INCREMENT && previousTarget)
						result = Token.findByType(Token.Type.SUFFIX_INCREMENT);
					else if (result.type == Token.Type.SUFFIX_DECREMENT && !previousTarget)
						result = Token.findByType(Token.Type.PREFIX_DECREMENT);
					else if (result.type == Token.Type.PREFIX_DECREMENT && previousTarget)
						result = Token.findByType(Token.Type.SUFFIX_DECREMENT);

					// 발견된 토큰을 쓴다
					tokens.push(result);

					// 버퍼 초기화
					buffer = "";
					continue;
				}
			}

			// 버퍼에 현재 문자를 쓴다
			buffer += char;
		}

		// 버퍼가 남았다면 마지막으로 써 준다
		if (isNumber) {
			tokens.push(new Token(Token.Type.NUMBER, buffer));
		} else {
			var token:Token = Token.findByValue(StringTools.trim(buffer), true);
			if (buffer.length > 0 && token != null)
				tokens.push(token);
		}

		if (isString)
			Debug.report("구문 오류", "문자열이 종결되지 않았습니다.", processingLine);

		return tokens;
	}
	
	/**
	 * 어휘 분석에 사용될 토큰을 정의한다.
	 */
	public function defineTokens():Void {
		
		Token.define(null, Token.Type.STRING);
		Token.define(null, Token.Type.NUMBER);
		Token.define(null, Token.Type.ARRAY);
		Token.define(null, Token.Type.CAST_TO_NUMBER);
		Token.define(null, Token.Type.CAST_TO_STRING);
		Token.define(null, Token.Type.APPEND);
		Token.define(null, Token.Type.APPEND_ASSIGNMENT);
		Token.define(null, Token.Type.ARRAY_REFERENCE);
		Token.define(null, Token.Type.INSTANCE);
		Token.define(null, Token.Type.LOAD_CONTEXT);
		Token.define(null, Token.Type.CHAR_AT);

		Token.define("var", Token.Type.VARIABLE, true);
		Token.define("function", Token.Type.FUNCTION, true);
		Token.define("class", Token.Type.CLASS, true);
		Token.define("if", Token.Type.IF, true);
		Token.define("elif", Token.Type.ELSE_IF, true);
		Token.define("else", Token.Type.ELSE, true);
		Token.define("for", Token.Type.FOR, true);
		Token.define("while", Token.Type.WHILE, true);
		Token.define("continue", Token.Type.CONTINUE, true);
		Token.define("break", Token.Type.BREAK, true);
		Token.define("return", Token.Type.RETURN, true);
		Token.define("new", Token.Type.NEW, true);
		Token.define("true", Token.Type.TRUE, true);
		Token.define("false", Token.Type.FALSE, true);
		Token.define("as", Token.Type.AS, true);

		Token.define("[", Token.Type.ARRAY_OPEN, false);
		Token.define("]", Token.Type.ARRAY_CLOSE, false);
		Token.define("{", Token.Type.BLOCK_OPEN, false);
		Token.define("}", Token.Type.BLOCK_CLOSE, false);
		Token.define("(", Token.Type.SHELL_OPEN, false);
		Token.define(")", Token.Type.SHELL_CLOSE, false);
		Token.define("->", Token.Type.RIGHT, false);
		Token.define(".", Token.Type.DOT, false);
		Token.define(",", Token.Type.COMMA, false);
		Token.define(":", Token.Type.COLON, false);
		Token.define(";", Token.Type.SEMICOLON, false);
		Token.define("++", Token.Type.PREFIX_INCREMENT, false, Token.Affix.PREFIX);
		Token.define("--", Token.Type.PREFIX_DECREMENT, false, Token.Affix.PREFIX);
		Token.define("++", Token.Type.SUFFIX_INCREMENT, false, Token.Affix.SUFFIX);
		Token.define("--", Token.Type.SUFFIX_DECREMENT, false, Token.Affix.SUFFIX);
		Token.define("+", Token.Type.UNRARY_PLUS, false, Token.Affix.PREFIX);
		Token.define("-", Token.Type.UNRARY_MINUS, false, Token.Affix.PREFIX);
		Token.define("=", Token.Type.ASSIGNMENT, false);
		Token.define("+=", Token.Type.ADDITION_ASSIGNMENT, false);
		Token.define("-=", Token.Type.SUBTRACTION_ASSIGNMENT, false);
		Token.define("*=", Token.Type.MULTIPLICATION_ASSIGNMENT, false);
		Token.define("/=", Token.Type.DIVISION_ASSIGNMENT, false);
		Token.define("%=", Token.Type.MODULO_ASSIGNMENT, false);
		Token.define("&=", Token.Type.BITWISE_AND_ASSIGNMENT, false);
		Token.define("^=", Token.Type.BITWISE_XOR_ASSIGNMENT, false);
		Token.define("|=", Token.Type.BITWISE_OR_ASSIGNMENT, false);
		Token.define("<<=", Token.Type.BITWISE_LEFT_SHIFT_ASSIGNMENT, false);
		Token.define(">>=", Token.Type.BITWISE_RIGHT_SHIFT_ASSIGNMENT, false);
		Token.define("==", Token.Type.EQUAL_TO, false);
		Token.define("!=", Token.Type.NOT_EQUAL_TO, false);
		Token.define(">", Token.Type.GREATER_THAN, false);
		Token.define(">=", Token.Type.GREATER_THAN_OR_EQUAL_TO, false);
		Token.define(">", Token.Type.LESS_THAN, false);
		Token.define("<=", Token.Type.LESS_THAN_OR_EQUAL_TO, false);
		Token.define("+", Token.Type.ADDITION, false);
		Token.define("-", Token.Type.SUBTRACTION, false);
		Token.define("*", Token.Type.MULTIPLICATION, false);
		Token.define("/", Token.Type.DIVISION, false);
		Token.define("%", Token.Type.MODULO, false);
		Token.define("!", Token.Type.LOGICAL_NOT, false, Token.Affix.PREFIX);
		Token.define("not", Token.Type.LOGICAL_NOT, true, Token.Affix.PREFIX);
		Token.define("&&", Token.Type.LOGICAL_AND, false);
		Token.define("and", Token.Type.LOGICAL_AND, true);
		Token.define("||", Token.Type.LOGICAL_OR, false);
		Token.define("or", Token.Type.LOGICAL_OR, true);
		Token.define("~", Token.Type.BITWISE_NOT, false, Token.Affix.PREFIX);
		Token.define("&", Token.Type.BITWISE_AND, false);
		Token.define("|", Token.Type.BITWISE_OR, false);
		Token.define("^", Token.Type.BITWISE_XOR, false);
		Token.define("<<", Token.Type.BITWISE_LEFT_SHIFT, false);
		Token.define(">>", Token.Type.BITWISE_RIGHT_SHIFT, false);
	}
	
	/**
	 * 어휘 분석이 끝난 계층 트리의 구조를 보여준다.
	 * 
	 * @param units
	 * @param level
	 */
	public function viewHierarchy(tree:Lextree, level:Int):Void {
		
		var space:String = "";
		
		for (i in 0...level)
			space += "      ";
			
		for (i in 0...tree.branch.length) {
			
			// 새 가지일 때
			if (tree.branch[i].hasBranch) {
				Sys.print(space + "<begin>\n");
				viewHierarchy(tree.branch[i], level + 1);
				Sys.print(space + "<end>\n");
			}
			
			// 어휘 데이터일 때
			else {
				if (tree.branch[i].lexData.length < 1)
					continue;
					
					
				var buffer:String =  "";
				for (j in 0...tree.branch[i].lexData.length) {
					var token:Token = tree.branch[i].lexData[j];
					buffer += StringTools.trim(token.value) + "@" + token.type + ",";
				}
				Sys.print(space + buffer+"\n");
			}
		}
	}
}


/**
 * 어휘 트리
 */
class Lextree {
	
	/**
	 * 파생 가지가 있는지의 여부
	 */
	public var hasBranch:Bool = false;
	
	/**
	 * 파생 가지
	 */
	public var branch:Array<Lextree>;
	
	/**
	 * 어휘 데이터 (잎사귀)
	 */
	public var lexData:Array<Token>;
	
	/**
	 * 컴파일 시 에러 출력에 사용되는 라인 넘버
	 */
	public var lineNumber:Int = 1;
	
	public function new(hasBranch:Bool, lineNumber:Int) {
		
		this.hasBranch = hasBranch;
		this.lineNumber = lineNumber;
		
		if (hasBranch)
			branch = new Array<Lextree>();
	}
	
}