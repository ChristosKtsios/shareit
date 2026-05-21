import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(emoji:'🗺️', title:'Βρες τι χρειάζεσαι κοντά σου', body:'Ο χάρτης δείχνει αγγελίες από ανθρώπους στη γειτονιά σου σε πραγματικό χρόνο.'),
    _OnboardingPage(emoji:'🤝', title:'Ανταλλάξτε, βοηθήστε, μοιραστείτε', body:'Δάνεισε εργαλεία, πρόσφερε υπηρεσίες, βρες παρέα. Η κοινότητα είναι εδώ.'),
    _OnboardingPage(emoji:'⭐', title:'Χτίστε εμπιστοσύνη μαζί', body:'Κάθε ανταλλαγή αφήνει αξιολόγηση. Το προφίλ σου δείχνει ποιος είσαι.'),
  ];

  Future<void> _done() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.onboardingKey, true);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Column(children: [
        Expanded(child: PageView.builder(
          controller: _controller,
          onPageChanged: (i) => setState(()=>_page=i),
          itemCount: _pages.length,
          itemBuilder: (_,i) => _pages[i],
        )),
        // Dots
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pages.length,(i)=>AnimatedContainer(
            duration: const Duration(milliseconds:200),
            margin: const EdgeInsets.symmetric(horizontal:4,vertical:20),
            width: i==_page?24:8, height:8,
            decoration: BoxDecoration(
              color: i==_page?AppColors.primary:AppColors.border,
              borderRadius: BorderRadius.circular(4)),
          )),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(24,0,24,24),
          child: ElevatedButton(
            onPressed: _page<_pages.length-1
                ? () => _controller.nextPage(duration:const Duration(milliseconds:300),curve:Curves.easeInOut)
                : _done,
            child: Text(_page<_pages.length-1?'Συνέχεια':'Ξεκίνα'),
          ),
        ),
      ])),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final String emoji, title, body;
  const _OnboardingPage({required this.emoji,required this.title,required this.body});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal:40),
    child: Column(mainAxisAlignment:MainAxisAlignment.center,children:[
      Text(emoji,style:const TextStyle(fontSize:72)),
      const SizedBox(height:32),
      Text(title,style:const TextStyle(color:AppColors.textPrimary,fontSize:24,fontWeight:FontWeight.w700,height:1.2),textAlign:TextAlign.center),
      const SizedBox(height:16),
      Text(body,style:const TextStyle(color:AppColors.textSecondary,fontSize:16,height:1.6),textAlign:TextAlign.center),
    ]),
  );
}
