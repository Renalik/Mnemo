import Foundation

public struct AppTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let ru: String
    public let en: String
    public let dark: Bool
    public let background: String
    public let accent: String
    public let glow: String
    public var text: String { dark ? "FFFFFF" : "13151B" }
    public var muted: String { dark ? "C5C2C4" : "4D5260" }
    public var buttonText: String { Palette.contrastText(accent) }
    public func name(_ lang: Language) -> String { lang.text(ru, en) }
    public static let all: [AppTheme] = [
        .init(id:"black",ru:"Полностью чёрная",en:"Black",dark:true,background:"000000",accent:"FFFFFF",glow:"262626"),
        .init(id:"white",ru:"Полностью белая",en:"White",dark:false,background:"FFFFFF",accent:"171717",glow:"E0E0E0"),
        .init(id:"mono",ru:"Чёрно-белая",en:"Monochrome",dark:true,background:"080808",accent:"FFFFFF",glow:"787878"),
        .init(id:"orange",ru:"Чёрно-оранжевая",en:"Ember",dark:true,background:"080605",accent:"FF851B",glow:"B94800"),
        .init(id:"blue",ru:"Бело-голубая",en:"Sky",dark:false,background:"EFF8FF",accent:"1769DC",glow:"8AD3FF"),
        .init(id:"aurora",ru:"Аврора",en:"Aurora",dark:true,background:"041B20",accent:"43F1B1",glow:"4A29B2"),
        .init(id:"sunset",ru:"Закат",en:"Sunset",dark:true,background:"200919",accent:"FF79BC",glow:"F16F10"),
        .init(id:"ocean",ru:"Океан",en:"Ocean",dark:true,background:"031C2E",accent:"39D2FF",glow:"0052AC"),
        .init(id:"neon",ru:"Неон",en:"Neon",dark:true,background:"12071D",accent:"FF40DA",glow:"144C91"),
        .init(id:"lavender",ru:"Лаванда",en:"Lavender",dark:false,background:"F2EBFF",accent:"6D40D0",glow:"CEB8FF"),
        .init(id:"mint",ru:"Мята",en:"Mint",dark:false,background:"E9FFF5",accent:"08785A",glow:"9DEDD0"),
        .init(id:"sakura",ru:"Сакура",en:"Sakura",dark:false,background:"FFF0F5",accent:"B9255B",glow:"FFB3CC"),
        .init(id:"cosmos",ru:"Космос",en:"Cosmos",dark:true,background:"0D0825",accent:"B49BFF",glow:"4320A5"),
        .init(id:"graphite",ru:"Графит",en:"Graphite",dark:true,background:"14191F",accent:"9EBFFF",glow:"44566F"),
        .init(id:"emerald",ru:"Изумруд",en:"Emerald",dark:true,background:"041C14",accent:"ECD67A",glow:"08734A"),
        .init(id:"ruby",ru:"Рубин",en:"Ruby",dark:true,background:"240711",accent:"FF6788",glow:"970F36"),
        .init(id:"midnight",ru:"Полночь",en:"Midnight",dark:true,background:"060D29",accent:"8EADFF",glow:"2036A8"),
        .init(id:"sand",ru:"Песок",en:"Sand",dark:false,background:"FCF2E1",accent:"914406",glow:"E9C28E"),
        .init(id:"champagne",ru:"Шампань",en:"Champagne",dark:false,background:"FCF9ED",accent:"79600B",glow:"E7D98C"),
        .init(id:"peach",ru:"Персик",en:"Peach",dark:false,background:"FFF1E8",accent:"C53E1B",glow:"FFB38D"),
        .init(id:"forest",ru:"Лес",en:"Forest",dark:true,background:"071C0D",accent:"94E69B",glow:"22672A"),
        .init(id:"coffee",ru:"Кофе",en:"Coffee",dark:true,background:"20160C",accent:"EBB679",glow:"885329"),
        .init(id:"lemonade",ru:"Лимонад",en:"Lemonade",dark:false,background:"FBFFE6",accent:"087B71",glow:"9FE7DB"),
        .init(id:"hologram",ru:"Голограмма",en:"Hologram",dark:false,background:"F7EEFF",accent:"6340DE",glow:"9DE9F3"),
        .init(id:"arctic",ru:"Арктика",en:"Arctic",dark:true,background:"031F2A",accent:"8FF8FF",glow:"12617B"),
        .init(id:"plum",ru:"Слива",en:"Plum",dark:true,background:"200B2D",accent:"DE9CFF",glow:"722999")
    ]
    public static func find(_ id: String) -> AppTheme { all.first { $0.id == id } ?? all[3] }
}

public struct Palette: Sendable {
    public let ru: String
    public let en: String
    public let hex: String
    public static let all = [
        Palette(ru:"Графит",en:"Graphite",hex:"303439"), .init(ru:"Снег",en:"Snow",hex:"F1F3F6"),
        .init(ru:"Коралл",en:"Coral",hex:"FF706A"), .init(ru:"Мандарин",en:"Tangerine",hex:"FF971C"),
        .init(ru:"Янтарь",en:"Amber",hex:"F7C716"), .init(ru:"Лимон",en:"Lemon",hex:"F2EB55"),
        .init(ru:"Олива",en:"Olive",hex:"5C702B"), .init(ru:"Мята",en:"Mint",hex:"69DCBB"),
        .init(ru:"Изумруд",en:"Emerald",hex:"087653"), .init(ru:"Бирюза",en:"Turquoise",hex:"0BB7AE"),
        .init(ru:"Лагуна",en:"Lagoon",hex:"087DB4"), .init(ru:"Небо",en:"Sky",hex:"9ACFFB"),
        .init(ru:"Кобальт",en:"Cobalt",hex:"2546CD"), .init(ru:"Индиго",en:"Indigo",hex:"4834B5"),
        .init(ru:"Сирень",en:"Lilac",hex:"B59AF3"), .init(ru:"Аметист",en:"Amethyst",hex:"7227A7"),
        .init(ru:"Фуксия",en:"Fuchsia",hex:"BA208C"), .init(ru:"Сакура",en:"Sakura",hex:"FFBDCF"),
        .init(ru:"Рубин",en:"Ruby",hex:"AA153E"), .init(ru:"Какао",en:"Cocoa",hex:"68462F"),
        .init(ru:"Песок",en:"Sand",hex:"E6CFA9"), .init(ru:"Шалфей",en:"Sage",hex:"9AB3A8"),
        .init(ru:"Сталь",en:"Steel",hex:"536378"), .init(ru:"Полночь",en:"Midnight",hex:"101831"),
        .init(ru:"Персик",en:"Peach",hex:"FFB68E")
    ]
    public static func luminance(_ hex: String) -> Double {
        let value = UInt64(hex, radix: 16) ?? 0
        let c = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { x -> Double in
            let s = x / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722
    }
    public static func contrastText(_ hex: String) -> String { luminance(hex) > 0.179 ? "000000" : "FFFFFF" }
}

public struct CardTheme: Identifiable, Sendable {
    public let id: Int
    public init(id: Int) { self.id = min(149, max(0, id)) }
    public var palette: Palette { Palette.all[id % 25] }
    public var category: Int { id / 25 }
    public var variant: Int { id % 5 }
    public var text: String { Palette.contrastText(palette.hex) }
    public static let categoriesRU = ["Однотонные", "Градиенты", "Узоры", "Геометрия", "Многоцветные", "Текстуры"]
    public static let categoriesEN = ["Solid", "Gradients", "Patterns", "Geometry", "Multicolor", "Textures"]
    public func name(_ language: Language) -> String {
        let title = language.text(palette.ru, palette.en)
        let stylesRU = ["Горошек", "Полоски", "Сетка", "Волны", "Клетка"]
        let stylesEN = ["Dots", "Stripes", "Grid", "Waves", "Checks"]
        let detail: String
        switch category {
        case 0, 1: detail = language.text(Self.categoriesRU[category], Self.categoriesEN[category])
        case 2: detail = language.text(stylesRU[variant], stylesEN[variant])
        case 3: detail = language.text(["Ромбы", "Зигзаг", "Лучи", "Круги", "Треугольники"][variant], ["Diamonds", "Zigzag", "Rays", "Circles", "Triangles"][variant])
        case 4: detail = language.text(["Радуга", "Призма", "Мираж", "Калейдоскоп", "Голограмма"][variant], ["Rainbow", "Prism", "Mirage", "Kaleidoscope", "Hologram"][variant])
        default: detail = language.text(["Мрамор", "Шёлк", "Иней", "Зерно", "Бумага"][variant], ["Marble", "Silk", "Frost", "Grain", "Paper"][variant])
        }
        return title + " · " + detail
    }
    public static let all = (0..<150).map { CardTheme(id: $0) }
}
