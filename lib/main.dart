import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const blue = Color(0xFF258EDB);
const navy = Color(0xFF1769A8);
String dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String normalize(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class Word {
  String id, word, meaning, example, level;
  bool custom;
  int repetitions, interval;
  String? due;
  Word({required this.id, required this.word, required this.meaning, required this.example, required this.level, this.custom=false, this.repetitions=0, this.interval=0, this.due});
  factory Word.fromJson(Map<String,dynamic> j) => Word(id:j['id'],word:j['word'],meaning:j['meaning'],example:j['example']??'',level:j['level']??'elementary',custom:j['custom']??false,repetitions:j['repetitions']??0,interval:j['interval']??0,due:j['due']);
  Map<String,dynamic> toJson() => {'id':id,'word':word,'meaning':meaning,'example':example,'level':level,'custom':custom,'repetitions':repetitions,'interval':interval,'due':due};
}

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const BrainUpApp()); }
class BrainUpApp extends StatelessWidget {
  const BrainUpApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(title:'브레인업',debugShowCheckedModeBanner:false,theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:blue),scaffoldBackgroundColor:const Color(0xFFF3F9FE),appBarTheme:const AppBarTheme(backgroundColor:blue,foregroundColor:Colors.white),filledButtonTheme:FilledButtonThemeData(style:FilledButton.styleFrom(backgroundColor:blue,padding:const EdgeInsets.symmetric(vertical:16,horizontal:20))),inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder())),home:const Home());
}

class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState()=>_HomeState(); }
class _HomeState extends State<Home> {
  List<Word> words=[];
  Map<String,dynamic> history={};
  String? installedOn;
  List<Word> plan=[];
  int tab=0;
  DateTime month=DateTime(DateTime.now().year,DateTime.now().month);
  bool loading=true;
  String get today=>dateKey(DateTime.now());
  Map<String,dynamic>? get todayRecord => history[today] is Map ? Map<String,dynamic>.from(history[today]) : null;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    final raw=p.getString('brainup_words');
    final loaded=raw==null ? (jsonDecode(await rootBundle.loadString('assets/words.json')) as List).map((x)=>Word.fromJson(Map<String,dynamic>.from(x))).toList() : (jsonDecode(raw) as List).map((x)=>Word.fromJson(Map<String,dynamic>.from(x))).toList();
    final h=Map<String,dynamic>.from(jsonDecode(p.getString('brainup_history')??'{}'));
    final firstRun=p.getString('brainup_installed_on')??today;
    await p.setString('brainup_installed_on',firstRun);
    setState(() {words=loaded;history=h;installedOn=firstRun;loading=false;});
    await save();
  }
  Future<void> save() async {final p=await SharedPreferences.getInstance();await p.setString('brainup_words',jsonEncode(words.map((x)=>x.toJson()).toList()));await p.setString('brainup_history',jsonEncode(history));}
  List<Word> getTodayPlan() {
    if(plan.isNotEmpty)return plan;
    final eligible=words.where((w)=>w.repetitions>0 && (w.due==null || w.due!.compareTo(today)<=0)).toList()..sort((a,b)=>(a.due??'').compareTo(b.due??''));
    final fresh=words.where((w)=>w.repetitions==0).take(10).toList();
    return [...eligible.take(20),...fresh];
  }
  void startQuiz({required bool practice}) {
    final current=getTodayPlan();
    if(current.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('오늘 학습할 단어가 없어요. 단어를 추가하거나 다음 복습일을 기다려 주세요.')));return;}
    if(!practice)plan=current;
    Navigator.of(context).push(MaterialPageRoute(builder:(_)=>QuizPage(words:current,practice:practice,onFinished:(results){
      if(!practice){
        final right=results.where((v)=>v).length;
        final passed=right/current.length>=.8;
        history[today]={'completed':true,'passed':passed || (todayRecord?['passed']==true),'correct':right,'total':current.length,'attempts':(todayRecord?['attempts']??0)+1};
        for(int i=0;i<current.length;i++){
          final w=current[i];
          if(results[i]){w.repetitions++;w.interval=w.repetitions==1?1:w.repetitions==2?3:min(90,w.interval*2);}
          else {w.repetitions=max(1,w.repetitions);w.interval=1;}
          w.due=dateKey(DateTime.now().add(Duration(days:w.interval)));
        }
        save();setState((){});
      }
    }))).then((_){setState((){});});
  }
  Future<void> addWord(String english,String meaning) async {
    if(words.any((w)=>normalize(w.word)==normalize(english))){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('이미 등록된 단어입니다.')));return;}
    setState(()=>words.add(Word(id:'custom_${DateTime.now().microsecondsSinceEpoch}',word:english.trim(),meaning:meaning.trim(),example:'',level:'custom',custom:true)));
    await save();
  }
  Future<void> deleteWord(Word word) async {setState(()=>words.removeWhere((w)=>w.id==word.id));await save();}
  @override Widget build(BuildContext context){
    if(loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final pages=[homePage(),wordPage(),statsPage(),settingsPage()];
    return Scaffold(appBar:AppBar(title:const Text('🧠 브레인업  BrainUp')),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:1100),child:pages[tab])),bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const [NavigationDestination(icon:Icon(Icons.calendar_month),label:'홈'),NavigationDestination(icon:Icon(Icons.menu_book),label:'단어장'),NavigationDestination(icon:Icon(Icons.bar_chart),label:'통계'),NavigationDestination(icon:Icon(Icons.settings),label:'설정')]));
  }
  Widget panel(Widget child)=>Card(color:Colors.white,margin:const EdgeInsets.symmetric(vertical:8),child:Padding(padding:const EdgeInsets.all(18),child:child));
  Widget homePage(){
    final p=getTodayPlan(); final fresh=p.where((w)=>w.repetitions==0).length;final review=p.length-fresh;
    return ListView(padding:const EdgeInsets.all(16),children:[panel(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month-1)),icon:const Icon(Icons.chevron_left)),Text('${month.year}년 ${month.month}월',style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold,color:navy)),IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month+1)),icon:const Icon(Icons.chevron_right))]),calendar(),const SizedBox(height:12),const Text('🔵 O: 목표 달성    🔴 X: 목표 미달성    ·: 오늘 진행 중',textAlign:TextAlign.center,style:TextStyle(fontSize:14))])),panel(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('오늘의 학습',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:12),Text('새 단어 $fresh/10개   ·   복습 단어 $review/20개',style:const TextStyle(fontSize:19)),const SizedBox(height:6),Text('오늘 평가 ${p.length}문제 · 통과 ${((p.length*.8).ceil())}문제 이상',style:const TextStyle(color:navy)),if(p.length<30)const Padding(padding:EdgeInsets.only(top:8),child:Text('초기 학습이나 복습 예정 단어가 부족한 날은 가능한 단어만 평가합니다.',style:TextStyle(color:Colors.black54))),const SizedBox(height:14),FilledButton.icon(onPressed:()=>startQuiz(practice:true),icon:const Icon(Icons.school),label:const Text('연습하기 · 즉시 피드백')),const SizedBox(height:8),FilledButton.icon(onPressed:()=>startQuiz(practice:false),icon:const Icon(Icons.edit),label:const Text('오늘의 평가 · 종료 후 채점')),if(todayRecord!=null)Padding(padding:const EdgeInsets.only(top:14),child:Text('오늘 기록: ${todayRecord!['correct']}/${todayRecord!['total']} · ${todayRecord!['passed']==true?'O 달성':'X 미달성'}',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)))]))]);
  }
  Widget calendar(){
    final first=DateTime(month.year,month.month,1).weekday%7;
    final count=DateTime(month.year,month.month+1,0).day;
    final cells=first+count;
    return Column(children:[Row(children:['일','월','화','수','목','금','토'].map((d)=>Expanded(child:Center(child:Text(d,style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold))))).toList()),const SizedBox(height:8),LayoutBuilder(builder:(context,c){final size=(c.maxWidth/7-5).clamp(43.0,100.0);return Wrap(spacing:5,runSpacing:5,children:List.generate(cells,(i){if(i<first)return SizedBox(width:size,height:size);final day=i-first+1;final key=dateKey(DateTime(month.year,month.month,day));final record=history[key];final isFuture=key.compareTo(today)>0;final isToday=key==today;final mark=record is Map ? (record['passed']==true?'O':'X') : (!isFuture&&!isToday && installedOn!=null && key.compareTo(installedOn!)>=0?'X':'');return Container(width:size,height:size,decoration:BoxDecoration(color:isToday?const Color(0xFFD7ECFB):const Color(0xFFF2F8FD),borderRadius:BorderRadius.circular(10),border:isToday?Border.all(color:blue,width:2):null),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('$day',style:const TextStyle(fontSize:13)),Text(mark,style:TextStyle(fontSize:(size*.42).clamp(22.0,38.0),fontWeight:FontWeight.w900,color:mark=='O'?blue:const Color(0xFFE1535B)))]));}));})]);
  }
  Widget wordPage()=>ListView(padding:const EdgeInsets.all(16),children:[panel(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[const Text('나만의 단어 추가',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('현재 버전은 뜻을 직접 입력해야 합니다. 자동 사전 검색은 다음 개발 단계에서 연결합니다.'),const SizedBox(height:12),FilledButton.icon(onPressed:()=>showAddDialog(),icon:const Icon(Icons.add),label:const Text('단어 추가'))])),panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('단어장 · ${words.length}개',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:8),...words.map((w)=>ListTile(title:Text(w.word,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text('${w.meaning} · ${w.repetitions==0?'미학습':'복습 ${w.due??''}'}'),trailing:w.custom?IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>deleteWord(w)):null))]))]);
  void showAddDialog(){final en=TextEditingController();final ko=TextEditingController();showDialog(context:context,builder:(ctx)=>AlertDialog(title:const Text('나만의 단어 등록'),content:SizedBox(width:400,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:en,decoration:const InputDecoration(labelText:'영어 단어')),const SizedBox(height:12),TextField(controller:ko,decoration:const InputDecoration(labelText:'한국어 뜻'))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('취소')),FilledButton(onPressed:(){if(en.text.trim().isEmpty||ko.text.trim().isEmpty)return;addWord(en.text,ko.text);Navigator.pop(ctx);},child:const Text('저장'))]));}
  Widget statsPage(){final values=history.values.whereType<Map>().toList();final success=values.where((x)=>x['passed']==true).length;return ListView(padding:const EdgeInsets.all(16),children:[panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('학습 통계',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:12),Text('학습한 날: ${values.length}일',style:const TextStyle(fontSize:20)),Text('O 달성: $success일',style:const TextStyle(fontSize:20)),Text('학습 경험 단어: ${words.where((w)=>w.repetitions>0).length}개',style:const TextStyle(fontSize:20)),const SizedBox(height:12),const Text('날짜별 상세 그래프는 후속 버전에서 추가합니다.')]))]);}
  Widget settingsPage()=>ListView(padding:const EdgeInsets.all(16),children:[panel(const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('브레인업 v0.1.0',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),SizedBox(height:12),Text('알림: 사용 안 함'),Text('목표: 신규 10개 + 복습 20개'),Text('출석: 평가 정답률 80% 이상'),Text('연습: 즉시 피드백 / 평가: 종료 후 피드백'),SizedBox(height:12),Text('데이터는 이 기기에 저장됩니다. 앱 데이터를 삭제하거나 앱을 제거하면 기록이 사라질 수 있습니다.',style:TextStyle(color:Colors.black54))]))]);}

class QuizPage extends StatefulWidget {
  final List<Word> words;final bool practice;final void Function(List<bool>) onFinished;
  const QuizPage({super.key,required this.words,required this.practice,required this.onFinished});
  @override State<QuizPage> createState()=>_QuizPageState();
}
class _QuizPageState extends State<QuizPage> {
  int index=0;bool revealed=false,finished=false;final controller=TextEditingController();final List<bool> results=[];final List<String> responses=[];
  bool get spelling => index%5!=3; // 80% English spelling, 20% Korean meaning
  Word get current=>widget.words[index];
  bool evaluate(Word w,String response,bool english){
    if(english)return normalize(response)==normalize(w.word);
    final accepted=w.meaning.split(RegExp(r'[,;/，、]')).map(normalize).where((s)=>s.isNotEmpty);
    return accepted.contains(normalize(response));
  }
  void submit(){if(controller.text.trim().isEmpty)return;final ok=evaluate(current,controller.text,spelling);results.add(ok);responses.add(controller.text);if(widget.practice)setState(()=>revealed=true);else advance();}
  void advance(){if(index+1>=widget.words.length){widget.onFinished(results);setState(()=>finished=true);}else setState((){index++;revealed=false;controller.clear();});}
  @override void dispose(){controller.dispose();super.dispose();}
  @override Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:Text(widget.practice?'연습 · 즉시 피드백':'평가 · 종료 후 채점')),body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:800),child:finished?resultView():ListView(padding:const EdgeInsets.all(20),children:[LinearProgressIndicator(value:(index+1)/widget.words.length,color:blue),const SizedBox(height:24),Text('${index+1} / ${widget.words.length}',style:const TextStyle(fontSize:18,color:navy)),const SizedBox(height:16),Card(child:Padding(padding:const EdgeInsets.all(26),child:Column(children:[Text(spelling?'다음 뜻에 해당하는 영어 단어를 입력하세요':'다음 영어 단어의 한국어 뜻을 입력하세요',textAlign:TextAlign.center),const SizedBox(height:18),Text(spelling?current.meaning:current.word,textAlign:TextAlign.center,style:const TextStyle(fontSize:30,fontWeight:FontWeight.bold,color:navy))]))),const SizedBox(height:18),TextField(controller:controller,enabled:!revealed,autofocus:true,textInputAction:TextInputAction.done,onSubmitted:(_){if(!revealed)submit();},decoration:InputDecoration(labelText:spelling?'영어 철자 입력':'한국어 뜻 입력',hintText:'정답을 입력하세요')),const SizedBox(height:18),if(revealed)...[Card(color:results.last?const Color(0xFFE9F7ED):const Color(0xFFFFF0F0),child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(results.last?'정답!':'오답',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Text('정답: ${spelling?current.word:current.meaning}',style:const TextStyle(fontSize:19)),if(current.example.isNotEmpty)Text('예문: ${current.example}')]))),const SizedBox(height:12),FilledButton(onPressed:advance,child:Text(index+1==widget.words.length?'연습 결과 보기':'다음 문제'))]else FilledButton(onPressed:submit,child:Text(widget.practice?'정답 확인':'답안 제출'))]))));
  }
  Widget resultView(){final count=results.where((x)=>x).length;final rate=count/results.length;return ListView(padding:const EdgeInsets.all(20),children:[Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[Icon(rate>=.8?Icons.check_circle:Icons.cancel,color:rate>=.8?blue:Colors.red,size:72),Text('${(rate*100).toStringAsFixed(1)}%',style:const TextStyle(fontSize:46,fontWeight:FontWeight.bold,color:navy)),Text('$count / ${results.length} 정답',style:const TextStyle(fontSize:20)),Text(widget.practice?'연습 완료':rate>=.8?'O · 오늘의 목표 달성':'X · 80% 미달성',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))]))),const SizedBox(height:12),const Text('문제별 정답 확인',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),...List.generate(widget.words.length,(i)=>Card(child:ListTile(leading:Icon(results[i]?Icons.check_circle:Icons.cancel,color:results[i]?blue:Colors.red),title:Text(widget.words[i].word),subtitle:Text('정답: ${widget.words[i].meaning}\n내 답: ${responses[i]}')))),const SizedBox(height:12),FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('홈으로 돌아가기'))]);}
}
