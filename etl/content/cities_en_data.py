"""Hand-authored English city blurbs for the 20 Demo hubs.

Seed corpus for ETL English city-text generation (Step 3 i18n). Translated from
the Chinese blurbs in etl/scripts/run_pipeline.py CITY_BLURBS. C-confidence
cities are covered by the generic template in generate_en_content.py instead.

Field names (suffix `_en` on the city record):
  overview_en, history_en, geography_en, economy_en, food_en, travel_en
"""

DEMO20_EN: dict[str, dict[str, str]] = {
    "atlanta": {
        "overview_en": (
            "Atlanta, the capital of Georgia, is one of the most important air "
            "gateways of the American South. The city is known for its Peachtree "
            "commercial corridors, civil-rights landmarks, and a fast-growing tech "
            "and media scene. Hartsfield-Jackson has long ranked among the world's "
            "busiest airports, making Atlanta a key node of the North American route network."
        ),
        "history_en": (
            "Railways drove its 19th-century rise, and the civil-rights movement left "
            "a deep mark in the 20th. Post-war aviation and conventions made Atlanta "
            "the economic centre of the American South."
        ),
        "geography_en": (
            "Perched on the southern edge of the Piedmont plateau, the city has a humid, "
            "warm climate with four distinct seasons — hot, humid summers and mild winters."
        ),
        "economy_en": (
            "Logistics, aviation, media, financial services and conventions anchor the "
            "economy, with dense clusters of corporate regional headquarters."
        ),
        "food_en": (
            "Southern classics, fried chicken, peach desserts and a rich mix of ethnic "
            "restaurants sit alongside the fast-food and local chains around the airport."
        ),
        "travel_en": (
            "Get around by metro and rental car; watch for summer thunderstorms that can "
            "disrupt flights. Local specialties are mostly food and souvenirs."
        ),
    },
    "dubai": {
        "overview_en": (
            "Dubai sits on the southern shore of the Arabian Gulf, and its ports, free "
            "trade zones and airline hub make it the great trading crossroads between "
            "Europe, Asia and Africa. Towering skyline meets desert, and tourism and "
            "retail are highly developed."
        ),
        "history_en": (
            "Started as a fishing and pearl-diving village; oil revenue and open trade "
            "policy powered ultra-fast urbanisation."
        ),
        "geography_en": (
            "Hot, arid desert climate with humid coasts; dust storms and extreme heat are "
            "things to plan around."
        ),
        "economy_en": (
            "Trade, logistics, tourism, finance and property are pillars; free zones "
            "attract a large number of cross-border companies."
        ),
        "food_en": (
            "Middle-Eastern spices, dates, nuts and street snacks abound, alongside a "
            "wealth of international restaurants."
        ),
        "travel_en": (
            "Metro and taxis are convenient; summer heat is extreme, so plan activities "
            "for early morning or evening."
        ),
    },
    "dallas": {
        "overview_en": (
            "The Dallas–Fort Worth metroplex is a major commercial and aviation centre "
            "of the American South. Finance, technology, energy and conventions are all "
            "active, and DFW ranks among the world's busiest hubs."
        ),
        "history_en": (
            "Rail and oil drove early prosperity; post-war aviation and suburbanisation "
            "shaped today's sprawling metroplex."
        ),
        "geography_en": (
            "North-Texas plains, with hot summers and occasional severe storms; the city "
            "spreads very wide."
        ),
        "economy_en": (
            "Energy, telecom, logistics, finance and tech start-ups all coexist."
        ),
        "food_en": (
            "Texas barbecue, Mexican flavours and a strong steakhouse culture stand out."
        ),
        "travel_en": (
            "You will rely on a car; the airport sits a fair distance from downtown."
        ),
    },
    "denver": {
        "overview_en": (
            "Denver sits against the Rockies as the high-altitude gateway of the American "
            "West. Outdoor gear and local food industries are distinctive, and tech, "
            "aerospace and tourism are growing fast."
        ),
        "history_en": (
            "The gold rush founded the city, and the railroad cemented its position as a "
            "western hub."
        ),
        "geography_en": (
            "Semi-arid high-plateau climate, sunny with big day/night swings and common "
            "winter snow."
        ),
        "economy_en": (
            "Aerospace, energy, technology and tourism all carry weight."
        ),
        "food_en": (
            "Local beer, beef and high-plateau farm products are popular (this game "
            "does not trade alcohol)."
        ),
        "travel_en": (
            "Watch for altitude effects; the airport is large and the walk between "
            "gates can be long."
        ),
    },
    "london": {
        "overview_en": (
            "London spans the Thames as Britain's capital and a world-class financial, "
            "media and education centre. Heathrow connects the city to major global "
            "cities, and London itself is one of Europe's most important consumer and "
            "tourist markets."
        ),
        "history_en": (
            "Settled since Roman times; the Industrial Revolution and imperial trade "
            "shaped the modern metropolis."
        ),
        "geography_en": (
            "Temperate maritime climate, rainy and cloudy much of the year; the "
            "metro area has grown far beyond the core."
        ),
        "economy_en": (
            "Finance, creative industries, professional services and tourism are the core."
        ),
        "food_en": (
            "Afternoon-tea treats, diverse immigrant cuisine and traditional market food "
            "coexist."
        ),
        "travel_en": (
            "Public transport is extensive; mind left-hand traffic and peak crowding."
        ),
    },
    "chicago": {
        "overview_en": (
            "Chicago stands on Lake Michigan, its skyline, logistics and Midwestern "
            "agricultural trade making it an inland American hub. O'Hare has long been "
            "a major international gateway."
        ),
        "history_en": (
            "Canals and railroads in the 19th century made it the 'railroad capital of "
            "America'; rebuilding after the Great Fire shaped the modern grid."
        ),
        "geography_en": (
            "Continental climate — cold winters, hot summers and a famous lake wind."
        ),
        "economy_en": (
            "Logistics, manufacturing, finance, agricultural trade and conventions."
        ),
        "food_en": (
            "Deep-dish pizza, hot dogs and Midwestern processed foods are famous "
            "(no alcohol traded)."
        ),
        "travel_en": (
            "City public transport works well; winter blizzards can affect flights."
        ),
    },
    "istanbul": {
        "overview_en": (
            "Istanbul bridges Europe and Asia, and the new airport has strengthened its "
            "place as a global aviation hub. A deep tradition of bazaars, spice trade "
            "and textiles continues today."
        ),
        "history_en": (
            "Ancient capital of Byzantium and the Ottoman Empire, remaining an economic "
            "and cultural centre in the modern republic."
        ),
        "geography_en": (
            "Mild, humid strait climate over hilly terrain; traffic congestion is common."
        ),
        "economy_en": (
            "Trade, tourism, textiles, manufacturing and aviation logistics."
        ),
        "food_en": (
            "Spices, Turkish delight, nuts and street-baked treats are everywhere."
        ),
        "travel_en": (
            "Ferries and metro link the two shores; expect haggling in bazaars and busy "
            "crowds."
        ),
    },
    "los_angeles": {
        "overview_en": (
            "The Los Angeles metro faces the Pacific as the West Coast's great "
            "entertainment and trade gateway. Port, film industry and diverse immigrant "
            "communities shape its consumer market."
        ),
        "history_en": (
            "Spanish colonial origins; 20th-century Hollywood and suburbanisation built "
            "its global image."
        ),
        "geography_en": (
            "Mediterranean climate, dry with little rain; the basin traps haze easily."
        ),
        "economy_en": (
            "Entertainment, international trade, technology and tourism."
        ),
        "food_en": (
            "Mexican flavours, Asian fusion and California produce."
        ),
        "travel_en": (
            "Deeply car-dependent; allow time for airport security and traffic."
        ),
    },
    "tokyo": {
        "overview_en": (
            "The Tokyo metro is one of the world's densest population and economic "
            "centres. Haneda serves the capital region, and the city excels at efficient "
            "transport, refined retail and a wide variety of regional specialties."
        ),
        "history_en": (
            "Grown from the seat of the Edo shogunate, modernised rapidly after the "
            "war into a global city."
        ),
        "geography_en": (
            "Humid subtropical climate; watch flights in the summer–autumn typhoon season."
        ),
        "economy_en": (
            "Finance, electronics, retail, cultural content and high-end manufacturing."
        ),
        "food_en": (
            "Wagashi sweets, tea snacks, processed seafood and region-limited snacks "
            "(no alcohol)."
        ),
        "travel_en": (
            "Public transport is superb; mind baggage limits in packed peak carriages."
        ),
    },
    "shanghai": {
        "overview_en": (
            "Shanghai sits at the mouth of the Yangtze as one of China's most important "
            "financial, shipping and trading cities. Pudong links Asia-Pacific hubs, and "
            "the consumer market is richly layered."
        ),
        "history_en": (
            "Treaty-port opening shaped its international role; modern Pudong "
            "development redrew the skyline."
        ),
        "geography_en": (
            "Subtropical monsoon climate — humid summers, cool winters, occasional "
            "typhoon effects."
        ),
        "economy_en": (
            "Finance, trade, shipping, advanced manufacturing and consumer retail."
        ),
        "food_en": (
            "Local dim sum, rice cakes, tea and modern creative foods."
        ),
        "travel_en": (
            "The metro network is extensive; Pudong airport is a long way from "
            "downtown."
        ),
    },
    "paris": {
        "overview_en": (
            "Paris is the French capital and a major European air gateway. Charles de "
            "Gaulle connects the city globally, and Paris is famed for its museums, "
            "fashion and refined food."
        ),
        "history_en": (
            "A medieval seat of royal power, it became a modern cultural capital after "
            "the Enlightenment and industrial age."
        ),
        "geography_en": (
            "Temperate climate with the Seine running through; the metro spreads far "
            "beyond the core."
        ),
        "economy_en": (
            "Tourism, fashion, luxury-industry value chains and professional services."
        ),
        "food_en": (
            "Pastries, chocolate, dairy desserts and regional specialties "
            "(no alcohol)."
        ),
        "travel_en": (
            "Metro and RER link the airports; mind rush hours and watch your bags."
        ),
    },
    "amsterdam": {
        "overview_en": (
            "Amsterdam is the Dutch capital, and Schiphol is one of Europe's most "
            "important connecting hubs. Canal networks, cycling culture and a strong "
            "trading tradition define the city."
        ),
        "history_en": (
            "Golden-Age maritime trade built its prosperity, and it remains a European "
            "logistics node."
        ),
        "geography_en": (
            "Lowland humid climate, rainy and windy; some areas sit below sea level."
        ),
        "economy_en": (
            "Logistics, trade, creative industries and agricultural-export services."
        ),
        "food_en": (
            "Cheese, chocolate, baked snacks and flower-related souvenirs."
        ),
        "travel_en": (
            "Bike lanes come first; the direct airport train to the city is very handy."
        ),
    },
    "guangzhou": {
        "overview_en": (
            "Guangzhou sits in the Pearl River Delta as southern China's trade and "
            "aviation gateway. Baiyun serves the south, and the city is famous for "
            "wholesale markets and Cantonese food culture."
        ),
        "history_en": (
            "An ancient port on the maritime Silk Road; the treaty-port trading "
            "tradition continues today."
        ),
        "geography_en": (
            "Humid subtropical, long warm seasons and a marked rainy period."
        ),
        "economy_en": (
            "Trade and wholesale, light manufacturing, conventions and logistics."
        ),
        "food_en": (
            "Cantonese dim sum, herbal-tea products, sweet soups and local snacks."
        ),
        "travel_en": (
            "Metro links the airport; mind the hot, humid weather for perishable goods."
        ),
    },
    "frankfurt": {
        "overview_en": (
            "Frankfurt is Germany's financial capital, and its airport is one of "
            "Europe's busiest connecting hubs. Conventions, banking and logistics form "
            "the city's economic backbone."
        ),
        "history_en": (
            "A medieval market town that grew into Germany's financial centre in the "
            "modern era."
        ),
        "geography_en": (
            "Temperate climate; the Rhine-Main metro is dense with traffic."
        ),
        "economy_en": (
            "Finance, conventions, aviation logistics and professional services."
        ),
        "food_en": (
            "Sausage delicatessen souvenirs, baked snacks and Black-Forest-style "
            "sweets (no alcohol)."
        ),
        "travel_en": (
            "The airport station reaches many European cities directly; transfer signs "
            "are clear."
        ),
    },
    "beijing": {
        "overview_en": (
            "Beijing is China's political and cultural capital. The Forbidden City "
            "axis and modern central business district coexist, and cultural-creative "
            "and specialty markets are lively."
        ),
        "history_en": (
            "Capital of the Liao, Jin, Yuan, Ming and Qing dynasties; national "
            "political and cultural centre in modern times."
        ),
        "geography_en": (
            "Temperate monsoon — dry winters, rainy summers, occasional spring dust."
        ),
        "economy_en": (
            "Public services, technology, cultural creativity, tourism and "
            "headquarters economy."
        ),
        "food_en": (
            "Beijing-style snacks, preserved fruit, tea and cultural-creative foods."
        ),
        "travel_en": (
            "Airport express and taxis work well; watch winter smog and flights."
        ),
    },
    "singapore": {
        "overview_en": (
            "Singapore commands the Malacca strait as Southeast Asia's aviation and "
            "trade hub. Changi is famed for efficiency and transshipment; the city-state "
            "is small but its trade and financial reach is large."
        ),
        "history_en": (
            "Grown from a colonial port, independent Singapore built its nation on "
            "trade and manufacturing."
        ),
        "geography_en": (
            "Tropical rainforest climate — hot and rainy all year."
        ),
        "economy_en": (
            "Trade, finance, logistics, electronics and tourism."
        ),
        "food_en": (
            "Nonya snacks, curry-related foods, jackfruit snacks and derived street-food "
            "products."
        ),
        "travel_en": (
            "Metro links the airport smoothly; strict public-order rules must be followed."
        ),
    },
    "seoul": {
        "overview_en": (
            "The Seoul metro is a major consumer and aviation market of Northeast Asia. "
            "Incheon serves international travellers, and the city is famous for pop "
            "culture, electronics and beauty industries."
        ),
        "history_en": (
            "Capital of the Joseon dynasty; rapid post-war industrialisation and "
            "urbanisation followed."
        ),
        "geography_en": (
            "Temperate monsoon with four distinct seasons — cold winters, hot summers."
        ),
        "economy_en": (
            "Electronics, pop culture, beauty, finance and tourism."
        ),
        "food_en": (
            "Kimchi-based processed foods, pastries, dried seaweed and derived "
            "street-snack products."
        ),
        "travel_en": (
            "Airport rail is convenient; mind Korean signs and peak-hour metro."
        ),
    },
    "hong_kong": {
        "overview_en": (
            "Hong Kong is a free-trade port and Asian aviation hub; the retail and "
            "food culture along Victoria Harbour is instantly recognisable."
        ),
        "history_en": (
            "A modern trading port that kept its international-hub role after the "
            "handover."
        ),
        "geography_en": (
            "Humid subtropical; mind the typhoon season."
        ),
        "economy_en": (
            "Finance, trade, logistics, tourism and professional services."
        ),
        "food_en": (
            "Egg rolls, pineapple-bun treats, tea and gift foods."
        ),
        "travel_en": (
            "The Airport Express is efficient; keep an eye on bags in crowded streets."
        ),
    },
    "bangkok": {
        "overview_en": (
            "Bangkok is Thailand's capital and a gateway for Southeast Asian tourism "
            "and aviation. Suvarnabhumi is a major regional hub; tourism, wholesale "
            "trade and food industries are active."
        ),
        "history_en": (
            "Capital of the Chakri dynasty, grown into a regional metropolis in the "
            "modern era."
        ),
        "geography_en": (
            "Tropical climate with occasional rainy-season floods; canals crisscross "
            "the city."
        ),
        "economy_en": (
            "Tourism, trade, food processing and light industry."
        ),
        "food_en": (
            "Spices, coconut treats, scarves and handicraft souvenirs."
        ),
        "travel_en": (
            "The airport is far from downtown; heat and humidity affect perishables."
        ),
    },
    "miami": {
        "overview_en": (
            "Miami is America's gateway to Latin America, where port, tourism and "
            "tropical vibes create a distinctive consumer market."
        ),
        "history_en": (
            "20th-century tourism and immigration drove its growth into an "
            "international city."
        ),
        "geography_en": (
            "Tropical/subtropical; mind hurricane-season flights."
        ),
        "economy_en": (
            "Tourism, trade, logistics, real estate and cruise-related services."
        ),
        "food_en": (
            "Processed tropical fruits, Cuban-style treats and Latin American "
            "specialties."
        ),
        "travel_en": (
            "Rental cars are common; watch summer storms and hurricane warnings."
        ),
    },
}
