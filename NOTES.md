Cześć, dzięki za podesłanie zadania! ;)

Przy tworzeniu tej aplikacji potraktowałem je trochę szerzej niż tylko jako typowe zadanie rekrutacyjne. Chciałem wykorzystać tę okazję również jako mały projekt własny, na którym mogłem sprawdzić w praktyce rzeczy, których nauczyłem się przez ostatnie lata. Dlatego projekt finalnie wyszedł trochę bardziej rozbudowany, niż było to konieczne do spełnienia samego zadania.

Przed rozpoczęciem implementacji poświęciłem sporo czasu na przygotowanie IMPLEMENTATION_PLAN.md. Najpierw razem z ChatGPT przygotowałem specjalny prompt zawierający dokładny opis tego, co chciałem zbudować: wymagania aplikacji, funkcjonalności, planowaną architekturę, technologie, sposób działania poszczególnych elementów oraz ogólny plan implementacji. Następnie przekazałem ten prompt do Cursor oraz Claude Opus 5, który na jego podstawie przygotował szczegółowy IMPLEMENTATION_PLAN.md.

Na tym etapie zaplanowałem między innymi wykorzystanie BLoC/Cubit, GetIt do dependency injection, podział na feature'y, rozdzielenie odpowiedzialności pomiędzy UI, logikę i dane, jedno współdzielone połączenie WebSocket oraz lokalne przechowywanie alertów w Hive. Chciałem też od początku mieć podstawy spójnego design systemu, zamiast dodawać wszystko dopiero na końcu.

Sam plan był jednak początkowo zbyt rozbudowany. Jeszcze przed rozpoczęciem implementacji uprościłem go i usunąłem sporą część niepotrzebnych abstrakcji i elementów. Można to również zobaczyć w historii commitów. Z perspektywy czasu widzę jednak, że powinienem poświęcić jeszcze więcej czasu na zweryfikowanie tego planu przed rozpoczęciem kodowania. Był bardzo szczegółowy i przez to część overengineeringu pojawiła się później mimo wcześniejszego uproszczenia. Lepsza weryfikacja na tym etapie pozwoliłaby uniknąć części późniejszych zmian.

Implementację podzieliłem na etapy i po każdym z nich robiłem własny code review, sprawdzając kod względem wcześniejszych założeń. W dużej części procesu korzystałem z AI, głównie z Claude Opus 5, które miało duży udział w implementacji większości etapów do około dziesiątego. Nie traktowałem jednak wygenerowanego kodu jako gotowego rozwiązania. W trakcie review upraszczałem część implementacji, poprawiałem ją i usuwałem rozwiązania, które uznałem za niepotrzebnie skomplikowane. Kilka razy pojawił się typowy dla pracy z AI overengineering, dlatego świadomie rezygnowałem z części zaproponowanych abstrakcji.

Szczególnie zależało mi na wykorzystaniu tego zadania do przećwiczenia WebSocketów i obsługi danych realtime, ponieważ jest to obszar, który chciałem lepiej poznać od strony praktycznej. Sam mechanizm został zaprojektowany tak, żeby jedno połączenie obsługiwało wiele instrumentów, a aplikacja radziła sobie również z reconnectem i ponowną subskrypcją.

Ostatni etap, czyli UI, zrobiłem już w dużej mierze samodzielnie. Najpierw przygotowałem projekt w Figmie, a następnie ręcznie zaimplementowałem go we Flutterze. Lubię ten etap pracy, dlatego chciałem sam przełożyć przygotowany design na finalny interfejs. Część widgetów użyłem ze swoich innych projektów.

Finalnie projekt jest więc połączeniem mojego wcześniejszego planowania, własnych decyzji i zmian oraz dużego wykorzystania AI jako narzędzia programistycznego. Nie chciałem udawać, że cały kod został napisany ręcznie, bo nie byłoby to zgodne z prawdą. Ważniejsze było dla mnie to, żeby rozumieć powstały kod, weryfikować go na kolejnych etapach i umieć uzasadnić zastosowane rozwiązania.

Gdybym miał więcej czasu, poświęciłbym go przede wszystkim na dokładniejsze przygotowanie i zweryfikowanie IMPLEMENTATION_PLAN.md przed rozpoczęciem implementacji. Sam proces tworzenia planu był już bardzo rozbudowany, a dodatkowy czas na jego review pozwoliłby wcześniej wychwycić więcej miejsc, w których pojawił się później overengineering, i ograniczyć liczbę niepotrzebnych zmian w trakcie implementacji.  
  
  
Dzięki za poświęcony czas na przejrzenie projektu. Mam nadzieję, że poza samym kodem udało mi się też pokazać trochę mojego sposobu myślenia i podejścia do tworzenia aplikacji. :)