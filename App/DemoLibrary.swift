import Foundation
import MnemoCore

enum DemoLibrary {
    /// Used exclusively with BOTH --ui-testing and --demo. Never seeds a real install.
    static func make() -> Library {
        var library = Library(); library.settings.onboardingComplete = true
        let english = Deck(name: "Английский B2", themeID: 88), anatomy = Deck(name: "Анатомия", themeID: 52)
        let history = Deck(name: "История XX века", themeID: 70), biology = Deck(name: "Биология", themeID: 57)
        library.decks = [english, anatomy, history, biology]
        for (deck, questions) in [
            (english, [("Что значит «meticulous»?", "Очень тщательный, скрупулёзный"), ("Что значит «ubiquitous»?", "Вездесущий, повсеместный"), ("Переведите «to procrastinate»", "Откладывать дела на потом")]),
            (anatomy, [("Сколько костей у взрослого человека?", "Обычно 206"), ("Какой орган вырабатывает инсулин?", "Поджелудочная железа")]),
            (history, [("В каком году закончилась Вторая мировая война?", "В 1945 году")]),
            (biology, [("Где в клетке идёт фотосинтез?", "В хлоропластах"), ("Какую молекулу используют клетки для переноса энергии?", "АТФ")])
        ] {
            for (question, answer) in questions { library.cards.append(Flashcard(deckID: deck.id, question: question, answer: answer)) }
        }
        return library
    }
}
