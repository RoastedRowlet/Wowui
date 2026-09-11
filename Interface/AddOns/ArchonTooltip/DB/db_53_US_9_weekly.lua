local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Unknown-Unknown','Warlock-Demonology','Monk-Windwalker','DemonHunter-Havoc','Paladin-Protection','Warlock-Destruction','Shaman-Elemental','Hunter-BeastMastery','Mage-Arcane','Rogue-Outlaw','Warlock-Affliction',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-09-08',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQADCggIEgAAAA==.',
Al='Alcha:BAAANQAECgIIAgAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAAANQAECgQIBAAAAA==.Algaefungi:BAAANQADCgYICgAAAA==.Althena:BAAANQADCgQIBAABNQAECgYICQABAAAAAA==.Alystana:BAAANQADCgUIBwAAAA==.',
An='Animeniac:BAAANQADCggIFQAAAA==.Anticlimax:BAAANQADCgYICAAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAAANQAECggIEwAAAA==.',
Ar='Artrael:BAAANQADCggICAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQADCgUICQABAAAAAA==.',
Av='Avienndha:BAAANQADCggIFQAAAA==.Avriel:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.',
Ba='Barbatos:BAAANQAECgEIAQAAAA==.',
Be='Beardeddrunk:BAAANQADCgUIBQAAAA==.',
Bo='Boochaka:BAAANQADCgcIDwAAAA==.Bouquet:BAAANQADCgYIEQAAAA==.',
Br='Brewdog:BAAANQAECgQIBAAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Busterposer:BAAANQAECgEIAQAAAA==.',
Ca='Calabooca:BAAANQADCgUICAAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAAANQADCggIFAAAAA==.',
Cl='Claptone:BAAANQADCgYIBwAAAA==.',
Co='Corpuscle:BAAANQADCgYIBgAAAA==.',
Cr='Critcomander:BAAANQAECgMIAwAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crueldin:BAAANQADCgYIBwAAAA==.',
Da='Dalsen:BAAANQAECgIIAwAAAA==.Dalvulpe:BAAANQADCgEIAQABNQAECgIIAwABAAAAAA==.Dankchop:BAAANQAECgEIAgAAAA==.Darklink:BAAANQADCgMIAwAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Denrin:BAAANQADCgMIAwAAAA==.',
Di='Diabolikal:BAAANQABCgQIBgABNQABCgUIBwABAAAAAA==.Dill:BAAANQAECgYICwAAAA==.',
Dm='Dmachine:BAAANQAECgIIBAABNQAECgkJFgACAI0iAA==.',
Do='Dondeezy:BAAANQABCgIIAgAAAA==.',
Dr='Drdru:BAAANQAECgQIBAABNQADCgUIBQABAAAAAA==.Dreadshade:BAAANQABCgEIAQAAAA==.Dropfort:BAAANQADCggIBwAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.',
Du='Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQABCgUIBwAAAA==.',
Ea='Easily:BAAANQAECgYICQAAAA==.',
El='Ellyanthia:BAAANQADCgcICAAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAECgkJFgACAI0iAA==.',
Ex='Exio:BAAANQAECgQICAAAAA==.',
Fa='Fastasheet:BAACNQAFFIEHAAIDAAUJKxH/AACkAQADAAUJKxH/AACkAQA1AAQKgRkAAgMACQnwIrACAFcDAAMACQnwIrACAFcDAAAA.',
Fi='Fill:BAAANQAECgcIDQAAAA==.',
Fl='Flehtwo:BAAANQAECggIEgAAAA==.Flyinbanana:BAAANQADCgIIAgABNQAECgEIAgABAAAAAA==.',
Fr='Fraglen:BAAANQADCgUIBQABNQAECgYICAABAAAAAA==.Frags:BAAANQAECgYICAAAAA==.',
Ge='Genjyosanzo:BAAANQADCggIEQAAAA==.',
Gh='Ghorn:BAAANQADCgcICgAAAA==.',
Gi='Gilljoww:BAAANQAECgYIDgAAAA==.',
Gn='Gnzz:BAAANQAECgMIAwAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAAANQAECgEIAQAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQADCggIDwAAAA==.',
Ho='Holyfed:BAAANQADCgQIBAAAAA==.Holyphok:BAAANQAECgEIAQAAAA==.Hotdog:BAAANQADCgcIBwAAAA==.',
Ic='Icestormy:BAAANQADCgUICgAAAA==.',
Ih='Ihavenofutur:BAAANQADCgQIBgAAAA==.',
Il='Iliil:BAAANQAECgQIBAAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAABNQAECoEYAAIEAAkJ6yO4AQCXAwAEAAkJ6yO4AQCXAwAAAA==.',
In='Inuk:BAAANQAECgMIAgAAAA==.',
Ir='Ironshaman:BAAANQAECgQIBAAAAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQADCgYIBgABAAAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAAANQAECgMIBAAAAA==.Jeryeth:BAAANQAECgYIDAAAAA==.Jeryzard:BAAANQADCgYIBwAAAA==.',
Ji='Jiannybon:BAAANQADCgQICAAAAA==.',
Ju='Judidench:BAAANQAECgcIBwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAEBNQAECoEZAAIFAAkJfSVeAADaAwAFAAkJfSVeAADaAwAAAA==.Kane:BAAANQAECgEIAQAAAA==.Kaïn:BAAANQADCgYIBgABNQAECgYICQABAAAAAA==.',
Ke='Kelsí:BAAANQADCggIFAAAAA==.',
Ki='Kiwí:BAAANQAECgQIBAAAAA==.',
Kr='Krasavice:BAAANQAECgQIBQAAAA==.Krenik:BAAANQADCggIEQAAAA==.Krimsondeath:BAAANQADCgQIBAAAAA==.Krisp:BAAANQADCgcIBwABNQADCgQIBAABAAAAAA==.',
Ku='Kurquaan:BAAANQADCgYIBgAAAA==.',
La='Lauranthalas:BAAANQADCggIFAAAAA==.Lavenderhaze:BAAANQADCgEIAQAAAA==.',
Le='Leathal:BAAANQADCggICQAAAA==.Lemurshoes:BAAANQAECgIIAgAAAA==.Lemursneaker:BAAANQADCgMIAwAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightshock:BAAANQADCgcIEQAAAA==.',
Lo='Lokust:BAAANQADCggIFgAAAA==.',
Lu='Lucentdawn:BAAANQADCggIEgAAAA==.',
Ly='Lycanius:BAAANQAECgUICwAAAA==.Lynqii:BAAANQAECgQIBQAAAA==.',
Ma='Malëk:BAAANQAECgYICQAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Mellowlizard:BAABNQAECoEWAAMCAAkJjSI6BQAVAwACAAgJxiI6BQAVAwAGAAMJ9h67JQD0AAAAAA==.Metuss:BAAANQADCgYIBgAAAA==.',
Mi='Miguel:BAAANQAECgUIDQAAAA==.Mira:BAAANQADCgcIEwAAAA==.',
Mk='Mkicon:BAAANQADCggIFgAAAA==.Mkultra:BAAANQADCgcIEwAAAA==.',
Mo='Mogmoog:BAAANQADCggIFAAAAA==.Moonangel:BAAANQADCggIFQAAAA==.Morbodan:BAAANQAECgQICAAAAA==.Motone:BAAANQAECgMIBAAAAA==.',
Mu='Multanni:BAAANQADCgcIEQAAAA==.',
My='Myonecrosis:BAAANQADCggIFQAAAA==.',
Na='Nakrog:BAAANQAECgUICwAAAA==.Napster:BAAANQADCgcIDAAAAA==.Nasa:BAABNQAECoEWAAIDAAkJKxgCCACbAgADAAkJKxgCCACbAgAAAA==.',
Ne='Nellarixi:BAAANQAECgYIDgAAAA==.Nethus:BAAANQADCgcICQAAAA==.',
Ni='Niivalyr:BAAANQABCgIIAQAAAA==.Nimbus:BAAANQADCggIDgABNQAECgkJTAAHAEskAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAAANQADCggIFQAAAA==.Nomäd:BAAANQADCggIDAAAAA==.Nosneb:BAAANQADCgEIAQABNQADCgYIBgABAAAAAA==.',
['Nì']='Nìtsua:BAAANQADCgYIBgAAAA==.',
Ob='Obilivion:BAAANQADCgQIBAAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAAANQAECgYIDgAAAA==.',
Ph='Phrash:BAAANQADCggIEAABNQAECgcIDQABAAAAAA==.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQADCgQIBAABNQAECgcIEAABAAAAAA==.',
Pr='Praystatioñ:BAAANQAECgQIBAAAAA==.Premiumgank:BAAANQABCgQIAgAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECoEVAAIIAAgJHxmpEgCTAgAIAAgJHxmpEgCTAgAAAA==.Racker:BAAANQADCgYIDwAAAA==.Ragou:BAAANQADCgQIBAAAAA==.',
Re='Rengots:BAAANQADCgYIBgAAAA==.Responsible:BAAANQAECgEIAQAAAA==.',
Rh='Rhaez:BAAANQADCggIDgAAAA==.',
Ro='Rogmash:BAAANQAECgQIBgAAAA==.Rokkoz:BAAANQAECgEIAQAAAA==.Romer:BAAANQAECgcIEQAAAA==.Rookiestar:BAAANQADCgcICgAAAA==.',
Sa='Sabb:BAAANQADCgYICgAAAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAAANQAECgUICAAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.',
Se='Sed:BAAANQADCggIFQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgMIAgAAAA==.',
Sh='Shadowmortis:BAAANQAECgQIBAAAAA==.Shirokhan:BAAANQAECgYIBAAAAA==.',
Si='Sidewinderx:BAAANQADCgEIAQAAAA==.Sinlock:BAAANQAECgYIDwAAAA==.',
Sk='Skrot:BAAANQADCgYIBgAAAA==.',
Sn='Snagglespark:BAAANQAECgQIBQAAAA==.Snowbunni:BAAANQADCgYIBwAAAA==.',
So='Soladrian:BAAANQADCgUIBQAAAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
St='Starz:BAAANQADCgYIBAAAAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgUIBQAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQADCgcIDAAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgEIAQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIAgAAAA==.Tankarmor:BAAANQADCggIFgAAAA==.Taylorswif:BAAANQAFFAEIAQAAAA==.',
Tc='Tcharta:BAAANQAECgEIAgAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Thermotide:BAAANQADCgQIBAAAAA==.Thoror:BAAANQADCgUIBQAAAA==.Thunderbolt:BAAANQADCgcIBwAAAA==.Thundernütz:BAAANQADCgIIAgAAAA==.Thymós:BAAANQAECgIIAgAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAAANQAECgQIBQAAAA==.Timeskip:BAAANQADCgYIBgAAAA==.Tinyfaith:BAAANQADCgYIBgAAAA==.Titum:BAAANQABCgYICwABNQAECggIEgAJAG8RAA==.',
To='Tongpooh:BAAANQAECgYICgABNQADCgYIBgABAAAAAA==.',
Tu='Tuckerherout:BAAANQAECgEIAwAAAA==.Tundro:BAAANQADCgUIBgAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.',
['Tî']='Tîtån:BAAANQADCggIDwAAAA==.',
Uh='Uh:BAAANQADCgYIBgABNQAECgcIDQABAAAAAA==.',
Un='Undeadlock:BAAANQADCgcIBwAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAAANQAECgcIEwAAAA==.',
Vi='Vindorei:BAAANQADCgUIBwAAAA==.',
Vo='Vokzhen:BAAANQAECgIIAgAAAA==.',
Wa='Walkerboah:BAAANQADCgYIDAAAAA==.',
We='Weel:BAAANQAECgQIBQAAAA==.',
Wy='Wyland:BAAANQAECgIIAgAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeromus:BAAANQADCggIDwAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAAANQADCggIDgAAAA==.',
Za='Zaboomaprune:BAAANQADCgYIBwAAAA==.Zarika:BAABNQAECoEWAAIKAAkJPiUtAADZAwAKAAkJPiUtAADZAwAAAA==.Zarì:BAAANQAECgIIAgABNQAECgkJFgAKAD4lAA==.',
Ze='Zeknull:BAAANQAECgUIBwAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zephy:BAAANQADCgcICQAAAA==.',
['Zä']='Zäo:BAABNQAECoEVAAQLAAkJuCH/AQAeAgALAAcJVCD/AQAeAgACAAMJkB5kUAALAQAGAAMJKRsuJAD/AAAAAA==.',
['Ïk']='Ïkea:BAAANQAECgQIBgAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
