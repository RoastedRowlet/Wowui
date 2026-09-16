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

local lookup = {'Unknown-Unknown','Mage-Arcane','Warlock-Demonology','Monk-Windwalker','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','DemonHunter-Havoc','Paladin-Protection','Warlock-Destruction','Priest-Shadow','Evoker-Preservation','Priest-Holy','Hunter-BeastMastery','Monk-Brewmaster','Rogue-Outlaw','Warlock-Affliction',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=53,date='2026-09-15',data={Ac='Acupuncher:BAAANQAECgIIAgAAAA==.',
Ad='Adamsandler:BAAANQADCggICAAAAA==.Adiwolf:BAAANQAECgIIAgAAAA==.',
Al='Alcha:BAAANQAECgMIBQAAAA==.Alenndar:BAAANQADCgEIAQAAAA==.Alexdaddario:BAAANQAECgQIBAAAAA==.Algaefungi:BAAANQAECgEIAwAAAA==.Althena:BAAANQADCgQIBAABNQAECgcIDwABAAAAAA==.Alystana:BAAANQADCgUIBwAAAA==.',
An='Anastera:BAAANQADCgYIBwAAAA==.Animeniac:BAAANQAECgIIAgAAAA==.Anticlimax:BAAANQAECgQIBAAAAA==.',
Ao='Aoibhneas:BAAANQADCgcIBwAAAA==.',
Ap='Apprentice:BAABNQAECoEWAAICAAkJ7iIPEQBiAwACAAkJ7iIPEQBiAwAAAA==.',
Ar='Artrael:BAAANQADCggICAAAAA==.',
At='Atorim:BAAANQADCgIIAgABNQADCgYIDwABAAAAAA==.',
Av='Avienndha:BAAANQAECgIIAgAAAA==.Avriel:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.',
Ba='Barbatos:BAAANQAECgEIAQAAAA==.',
Be='Beardeddrunk:BAAANQADCgUIBQAAAA==.Beornwildlaw:BAAANQABCgcIDgAAAA==.',
Bo='Boochaka:BAAANQAECgQIBAAAAA==.Bouquet:BAAANQAECgIIAgAAAA==.',
Br='Brewdog:BAAANQAECgQIBwAAAA==.Brickfists:BAAANQADCgQIBAAAAA==.Brotherfuzz:BAAANQAECgIIAwAAAA==.',
Bu='Busterposer:BAAANQAECgIIAgAAAA==.',
Ca='Calabooca:BAAANQADCgUICAAAAA==.Candor:BAAANQADCgUIBQAAAA==.',
Ch='Cheesefries:BAAANQAECgIIAgAAAA==.',
Cl='Claptone:BAAANQAECgEIAQAAAA==.',
Co='Corpuscle:BAAANQAECgQIBAAAAA==.',
Cr='Critcomander:BAAANQAECgUIBwAAAA==.Critties:BAAANQADCgMIAwAAAA==.Crueldin:BAAANQAECgEIAQAAAA==.',
Da='Dalsen:BAAANQAECgUICAAAAA==.Dalvulpe:BAAANQADCgEIAQABNQAECgUICAABAAAAAA==.Dankchop:BAAANQAECgEIAwAAAA==.Darkbishop:BAAANQABCgYICgAAAA==.Darklink:BAAANQADCgMIAwAAAA==.Dawnlighted:BAAANQADCgMIAwAAAA==.',
De='Denrin:BAAANQADCgUIBwAAAA==.',
Di='Diabolikal:BAAANQABCgQIBgABNQABCgUIBwABAAAAAA==.Dill:BAAANQAECgcIEgAAAA==.Divinesmite:BAAANQABCgcICAAAAA==.',
Dm='Dmachine:BAAANQAECgUICQABNQAECgkJHgADAOoiAA==.',
Do='Dondeezy:BAAANQABCgIIAgAAAA==.',
Dr='Drdru:BAAANQAECgQIBwABNQADCgUIBQABAAAAAA==.Dreadshade:BAAANQADCgcIBwAAAA==.Drscruffles:BAAANQADCgcIBwAAAA==.',
Du='Durkidurk:BAAANQADCgMIAwAAAA==.',
Dy='Dyabolykal:BAAANQABCgUIBwAAAA==.',
Ea='Easily:BAAANQAECgYIDgAAAA==.',
El='Ellyanthia:BAAANQADCggICQAAAA==.',
Em='Emachine:BAAANQADCgcIBwABNQAECgkJHgADAOoiAA==.',
Ex='Exio:BAAANQAECgQICAAAAA==.',
Fa='Fastasheet:BAACNQAFFIENAAIEAAYJeRMXAQAQAgAEAAYJeRMXAQAQAgA1AAQKgSIAAgQACQlVJQoBAMsDAAQACQlVJQoBAMsDAAAA.',
Fi='Fill:BAABNQAECoEXAAIFAAkJDyTxAACoAwAFAAkJDyTxAACoAwAAAA==.',
Fl='Flehtwo:BAABNQAECoEeAAMGAAkJHxqcFQDNAgAGAAkJHxqcFQDNAgAHAAgJQwp3OwDAAQAAAA==.Flyinbanana:BAAANQADCgIIAgABNQAECgQIBgABAAAAAA==.',
Fr='Fraglen:BAAANQADCgUIBQABNQAECgcICQABAAAAAA==.Frags:BAAANQAECgcICQAAAA==.',
Ge='Genjyosanzo:BAAANQAECgEIAQAAAA==.',
Gh='Ghorn:BAAANQADCgcICgAAAA==.Ghostkrim:BAAANQADCgUIBQAAAA==.',
Gi='Gilljoww:BAABNQAECoEZAAIIAAgJ/x63DwDGAgAIAAgJ/x63DwDGAgAAAA==.Gireigtulb:BAAANQADCgYIBgAAAA==.',
Gn='Gnzz:BAAANQAECgQIBwAAAA==.',
Go='Gocirr:BAAANQADCgUIBQAAAA==.',
Gr='Grito:BAAANQADCgYICgAAAA==.',
Ha='Haehn:BAAANQADCgMIAwAAAA==.Halstorm:BAAANQAECgMIAwAAAA==.Harrysax:BAAANQABCgYIBgAAAA==.',
He='Hexxytime:BAAANQADCgQIBAAAAA==.',
Hi='Hilazy:BAAANQAECgEIAQAAAA==.',
Hm='Hm:BAAANQADCggICAAAAA==.',
Ho='Holyfed:BAAANQADCgQIBAAAAA==.Holyphok:BAAANQAECgEIAQAAAA==.Hotdog:BAAANQADCgcIBwAAAA==.',
Ic='Icestormy:BAAANQADCgUICgAAAA==.',
Ih='Ihavenofutur:BAAANQADCgQIBgAAAA==.',
Il='Iliil:BAAANQAECgYICQAAAA==.Illbiteyou:BAAANQADCgQIBAAAAA==.Illidantwo:BAABNQAECoEZAAIJAAkJ6yM6BABwAwAJAAkJ6yM6BABwAwAAAA==.',
Im='Imprints:BAAANQAECgEIAQAAAA==.',
In='Inuk:BAAANQAECgUIBwAAAA==.',
Ir='Ironshaman:BAAANQAECgUIBwAAAA==.',
It='Italianapee:BAAANQADCggICAABNQAECgUIBwABAAAAAA==.',
Ja='Jabu:BAAANQADCgQIAwABNQAECgEIAQABAAAAAA==.Jaghatai:BAAANQADCgIIAgAAAA==.',
Je='Jenstonedart:BAAANQAECgQICQAAAA==.Jeryeth:BAAANQAECgcIEwAAAA==.Jeryzard:BAAANQADCgYIDAAAAA==.',
Ji='Jiannybon:BAAANQADCgQICwAAAA==.',
Ju='Judidench:BAAANQAECgcIBwAAAA==.Juicewillis:BAAANQADCgIIAgAAAA==.',
Ka='Kain:BAECNQAFFIEFAAIKAAMJiB0pAgAOAQAKAAMJiB0pAgAOAQA1AAQKgRkAAgoACQl9JdIAAMUDAAoACQl9JdIAAMUDAAAA.Kane:BAAANQAECgQIBQAAAA==.Karmasuture:BAAANQADCgYIBgABNQAECgMIAwABAAAAAA==.Kaïn:BAAANQADCgYIDAABNQAECgcIDwABAAAAAA==.',
Ke='Kelsí:BAAANQAECgIIAgAAAA==.',
Ki='Kiwí:BAAANQAECgUICQAAAA==.',
Kr='Krasavice:BAAANQAECgUICwAAAA==.Krenik:BAAANQADCggIHwAAAA==.Krimsondeath:BAAANQADCgQIBAAAAA==.Krisp:BAAANQADCggICAABNQADCgQIBAABAAAAAA==.',
Ku='Kurquaan:BAAANQADCggICAAAAA==.',
La='Lauranthalas:BAAANQAECgEIAQAAAA==.Lavenderhaze:BAAANQADCgEIAQAAAA==.',
Le='Leathal:BAAANQAECgIIAgAAAA==.Lemurshoes:BAAANQAECgIIAwAAAA==.Lemursneaker:BAAANQAECgQIBAAAAA==.Letsgomen:BAAANQADCgEIAQAAAA==.',
Li='Lightshock:BAAANQADCggIEwAAAA==.',
Ll='Llaagg:BAAANQADCgcIAQAAAA==.',
Lo='Lokust:BAAANQAECgEIAQAAAA==.',
Lu='Lucentdawn:BAAANQAECgEIAQAAAA==.Ludachris:BAAANQAECgEIAQAAAA==.',
Ly='Lycanius:BAAANQAECgUICwAAAA==.Lynqii:BAAANQAECgQICgAAAA==.',
Ma='Malëk:BAAANQAECgcIDwAAAA==.Maximus:BAAANQADCgUIBQAAAA==.',
Me='Medallis:BAAANQABCgMIBgAAAA==.Mellowlizard:BAABNQAECoEeAAMDAAkJ6iIeCgAZAwADAAgJLyMeCgAZAwALAAMJ9h70KgDrAAAAAA==.Metuss:BAAANQAECgEIAQAAAA==.',
Mi='Miguel:BAAANQAECgUIDQAAAA==.Mira:BAAANQAECgQIBAAAAA==.',
Mk='Mkicon:BAAANQAECgEIAQAAAA==.Mkultra:BAAANQAECgQIBAAAAA==.',
Mo='Mogmoog:BAAANQAECgIIAgAAAA==.Moonangel:BAAANQAECgIIAgAAAA==.Morbodan:BAAANQAECgYIDQAAAA==.Motone:BAAANQAECgMIBAAAAA==.',
Mu='Multanni:BAAANQAECgMIAwAAAA==.',
My='Myonecrosis:BAAANQAECgIIAgAAAA==.',
Na='Nakrog:BAAANQAECgYIEQAAAA==.Napster:BAAANQADCgcIDAAAAA==.Nasa:BAABNQAECoEeAAIEAAkJTRsLCQDMAgAEAAkJTRsLCQDMAgAAAA==.',
Ne='Nellarixi:BAABNQAECoEZAAIMAAgJaRuqCwDCAgAMAAgJaRuqCwDCAgAAAA==.Nethus:BAAANQADCgcICQAAAA==.',
Ni='Niivalyr:BAAANQABCgIIAQAAAA==.Nimbus:BAAANQADCggIDgABNQAECgkJTwAGAJckAA==.',
No='Nodens:BAAANQADCgcIEwAAAA==.Nomaa:BAAANQAECgIIAgAAAA==.Nomäd:BAAANQADCggIDAAAAA==.Nosneb:BAAANQADCgEIAQABNQADCgYICwABAAAAAA==.',
Ny='Nytedevil:BAAANQAECgEIAQAAAA==.',
['Nì']='Nìtsua:BAAANQADCgYICwAAAA==.',
Ob='Obilivion:BAAANQADCgYICgAAAA==.',
Og='Ogmount:BAAANQAECgMIAwAAAA==.',
Or='Orflame:BAABNQAECoEZAAINAAgJeQfpFwCPAQANAAgJeQfpFwCPAQAAAA==.',
Ph='Phrash:BAAANQAECgMIAwABNQAECgkJFwAFAA8kAA==.',
Pi='Pigbearmans:BAAANQADCgYIBgAAAA==.',
Pl='Plex:BAAANQADCgQIBAABNQAECggIGgAOAFAjAA==.',
Po='Pooldan:BAAANQAECgEIAQAAAA==.',
Pr='Praystatioñ:BAAANQAECgUICQAAAA==.Premiumgank:BAAANQABCgYIBAAAAA==.',
Pu='Purerform:BAAANQADCgcIBwAAAA==.',
Qu='Quelidra:BAAANQADCgUIBQAAAA==.Quepaspete:BAAANQADCgYIBwAAAA==.',
Ra='Raa:BAABNQAECoEYAAIPAAgJtRw+GQCyAgAPAAgJtRw+GQCyAgAAAA==.Racker:BAAANQADCgYIFQAAAA==.Ragou:BAAANQADCgQIBAAAAA==.',
Re='Rengots:BAAANQADCgYIDAAAAA==.Responsible:BAAANQAECgQIBQAAAA==.',
Rh='Rhaez:BAAANQADCggIFgAAAA==.',
Ro='Rogmash:BAAANQAECgQIBwAAAA==.Rokkoz:BAAANQAECgQIBQAAAA==.Romer:BAABNQAECoEdAAIQAAkJSwhkCwCvAQAQAAkJSwhkCwCvAQAAAA==.Rookiestar:BAAANQADCggIEgAAAA==.',
Sa='Sabb:BAAANQADCgYICgAAAA==.Saphroniå:BAAANQADCgcIGQAAAA==.Sass:BAAANQAECgcIDwAAAA==.Sazed:BAAANQADCgEIAQAAAA==.',
Sc='Schend:BAAANQADCgYICwAAAA==.',
Se='Sed:BAAANQAECgEIAQAAAA==.Serrana:BAAANQADCgUIBQAAAA==.',
Sf='Sfinktor:BAAANQADCgMIAgAAAA==.',
Sh='Shadowmortis:BAAANQAECgQIBAAAAA==.Shirokhan:BAAANQAECggIBwAAAA==.',
Si='Sidewinderx:BAAANQADCgEIAQAAAA==.Sinlock:BAABNQAECoEaAAMDAAgJkBzjHgB2AgADAAcJjBzjHgB2AgALAAQJMxFQJQARAQAAAA==.',
Sk='Skrot:BAAANQADCgYIBgAAAA==.',
Sn='Snagglespark:BAAANQAECgUICgAAAA==.Sneakylink:BAAANQADCgYIBgAAAA==.Snowbunni:BAAANQADCgYIBwAAAA==.',
So='Soladrian:BAAANQADCgYICgAAAA==.',
Sp='Spankyee:BAAANQADCgQIBAAAAA==.',
St='Starz:BAAANQADCgYIBAAAAA==.',
Su='Sunchipzz:BAAANQADCgQIBAAAAA==.Sundayschool:BAAANQAECgcIDAAAAA==.',
Sy='Syyia:BAAANQADCgIIAgAAAA==.',
['Sé']='Séraph:BAAANQAECgEIAQAAAA==.',
['Só']='Sóozabimaru:BAAANQAECgEIAQAAAA==.',
Ta='Tahano:BAAANQABCgIIAgAAAA==.Talljeff:BAAANQAECggIBAAAAA==.Tankarmor:BAAANQAECgEIAQAAAA==.Taylorswif:BAAANQAFFAIIAwAAAA==.',
Tc='Tcharta:BAAANQAECgQIBgAAAA==.',
Th='Thefamousone:BAAANQADCgYICAAAAA==.Thermotide:BAAANQAECgMIAwAAAA==.Thoror:BAAANQADCgYICwAAAA==.Thunderbolt:BAAANQADCgcIBwABNQADCggICAABAAAAAA==.Thundernütz:BAAANQADCgIIAgAAAA==.Thymós:BAAANQAECgIIAwAAAA==.',
Ti='Tiffina:BAAANQADCgYICQAAAA==.Tiffzen:BAAANQAECgUICgAAAA==.Timeskip:BAAANQADCggIBgAAAA==.Tinyfaith:BAAANQADCgYIBgAAAA==.Titum:BAAANQAECgQIBAABNQAECggIGQACAKMVAA==.',
To='Tongpooh:BAAANQAECgYIEAABNQADCgYIBgABAAAAAA==.',
Tr='Treeberk:BAAANQAECgEIAQAAAA==.',
Tu='Tuckerherout:BAAANQAECgYICQAAAA==.Tundro:BAAANQADCgUIBgAAAA==.',
Tw='Twix:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.',
['Tî']='Tîtån:BAAANQAECgEIAQAAAA==.',
Uh='Uh:BAAANQAECgUIBQABNQAECgkJFwAFAA8kAA==.',
Un='Undeadlock:BAAANQADCggICAAAAA==.',
Va='Vale:BAAANQADCgEIAQAAAA==.',
Vg='Vgmking:BAABNQAECoEaAAIIAAgJvA88KwDFAQAIAAgJvA88KwDFAQAAAA==.',
Vi='Vindorei:BAAANQADCgUIDgAAAA==.',
Vo='Vokzhen:BAAANQAECgQIBgAAAA==.',
Wa='Walkerboah:BAAANQAECgQIBAAAAA==.Warmachinne:BAAANQADCgYIBgAAAA==.',
We='Weel:BAAANQAECgUICwAAAA==.',
Wo='Wolfspider:BAAANQAECgEIAQAAAA==.',
Wy='Wyland:BAAANQAECgMIBQAAAA==.Wylandvoker:BAAANQADCgIIAgAAAA==.',
Xa='Xanun:BAAANQADCgMIAwAAAA==.',
Xe='Xeromus:BAAANQADCggIDwAAAA==.Xetsus:BAAANQADCgUIBQAAAA==.',
Ya='Yang:BAAANQABCgEIAQAAAA==.',
Yo='Yoink:BAAANQADCgUIBQAAAA==.',
Yu='Yuta:BAAANQADCgQIBAAAAA==.',
Yv='Yvelmaya:BAAANQAECgIIAgAAAA==.',
Za='Zaboomaprune:BAAANQAECgEIAQAAAA==.Zarika:BAABNQAECoEeAAIRAAkJpyUoAADlAwARAAkJpyUoAADlAwAAAA==.Zarì:BAAANQAECgUIBwABNQAECgkJHgARAKclAA==.',
Ze='Zeknull:BAAANQAECgYIDAAAAA==.Zenio:BAAANQADCgIIAgAAAA==.Zephy:BAAANQADCgcICQAAAA==.',
Zr='Zrgl:BAAANQADCggICAAAAA==.',
['Zä']='Zäo:BAABNQAECoEeAAQSAAkJ1iJQAACBAwASAAkJYyBQAACBAwADAAQJ8hwVYgBIAQALAAMJKRunKQDzAAAAAA==.',
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
