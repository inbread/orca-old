package elsa;
import elsa.vm.Beluga;
import elsa.debug.Debug;
import haxe.Utf8;
import sys.io.File;
/**
 * Orca Compiler & VM Launcher
 * 
 * @author 김 현준
 */
class BelugaLauncher {
	
	public static function main() {
		
		haxe.Log.trace = function (log, ?d) Sys.println(Std.string(log));
		
		trace("Orca BELUGA Compiler 2.0 (Unstable)");		
		
		// 테스트용 오르카 소스
		var temp_test:String = File.getContent("test/temp.orca");
		var variable_test:String = File.getContent("test/variable_test.orca");
		var function_test:String = File.getContent("test/function_test.orca");
		var array_test:String = File.getContent("test/array_test.orca");
		var class_test:String = File.getContent("test/class_test.orca");
		var if_test:String = File.getContent("test/if_test.orca");
		var for_test:String = File.getContent("test/for_test.orca");
		var while_test:String = File.getContent("test/while_test.orca");
		var include_test:String = File.getContent("test/include_test.orca");
		var evaluator:String = File.getContent("test/evaluator.orca");
		
		var parser:BelugaParser = new BelugaParser();
		
		var compiledCode:String = parser.compile(temp_test, "test/");
		trace(compiledCode);
		
		if (!Debug.errorReported){		
		
			var vm:Beluga = new Beluga();
			vm.load(compiledCode);
			
			trace("-----------------init-----------------");
			vm.run();
			trace("--------------------------------------");
		}
		trace("Press any key to exit...");
		Sys.getChar(false);
	}	
}