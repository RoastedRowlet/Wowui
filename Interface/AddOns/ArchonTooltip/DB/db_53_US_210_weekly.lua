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

local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Hunter-BeastMastery',}
local provider = {region='US',realm='Tanaris',name='US',type='weekly',zone=53,date='2026-09-08',data={Aa='Aalicya:BAAANQADCgUIBQAAAA==.',
Ac='Acegoblain:BAAANQAECgYIBwABNQAECggIFgABAAUYAA==.',
Ad='Adind:BAAANQAECgQIBQAAAA==.Adonra:BAAANQADCgYIBgAAAA==.',
Ae='Aerorising:BAAANQADCgYIBgAAAA==.',
Ak='Akkiba:BAAANQADCgQIBQAAAA==.',
Al='Aldabaran:BAAANQADCgcIDAAAAA==.Alestalker:BAAANQADCgUIBQABNQADCgUIBQACAAAAAA==.Aletheïa:BAAANQADCgYIBgAAAA==.Althamon:BAAANQADCgQIBQAAAA==.',
An='Antamun:BAAANQAECgUICgAAAA==.',
Ao='Aoasis:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.',
Aq='Aqueefer:BAAANQAECgUIBAAAAA==.',
Ar='Araethea:BAAANQAECgYIDQAAAA==.Arasettey:BAAANQADCggICAABNQAECgcIEAACAAAAAA==.Arislynn:BAAANQADCgcIDQAAAA==.Aryn:BAAANQAECgQIBAAAAA==.',
Az='Azirra:BAAANQADCgMIAwAAAA==.',
['Aù']='Aùriel:BAAANQAECgQIBQAAAA==.',
Ba='Badgerhollis:BAAANQADCgMIAwAAAA==.Bailey:BAAANQADCgcIBwAAAA==.Bamalock:BAAANQAECgEIAQAAAA==.Bathin:BAAANQAECgQIBQAAAA==.Bathwater:BAAANQAECgcIDAAAAA==.',
Be='Bearn:BAAANQADCgYIBgAAAA==.',
Bi='Biffster:BAAANQAECgQICAAAAA==.Bighellion:BAAANQADCgIIAgAAAA==.Bigpumps:BAAANQADCgEIAQABNQADCggICAACAAAAAA==.Bigtriangle:BAAANQAECgcIEAAAAA==.Billiamson:BAAANQADCgcIDQAAAA==.',
Bj='Bjoris:BAAANQAECgQIBQAAAA==.',
Bl='Bloodaxe:BAAANQADCggIBAAAAA==.',
Bo='Bornferal:BAAANQADCggICAAAAA==.',
Br='Bryzx:BAAANQAFFAIIAgAAAA==.Bryzxbless:BAAANQAECgEIAQAAAA==.',
Bu='Bubblebee:BAAANQAECgEIAQAAAA==.Bullan:BAAANQADCgEIAQAAAA==.Butterskotch:BAAANQADCgYIBgAAAA==.Buttpeanut:BAAANQADCggIFAAAAA==.',
Cl='Clairvoyance:BAAANQABCgMIAwABNQAECgQIBQACAAAAAA==.',
Cr='Crunchynuget:BAAANQAECgYIDAAAAA==.',
Cy='Cynemon:BAAANQADCgcIDQAAAA==.',
Da='Daifuku:BAAANQAECgUICAAAAA==.Darknonsence:BAAANQADCgIIAgAAAA==.David:BAAANQADCgQIBAABNQAECgQIBQACAAAAAA==.',
De='Demonetizeme:BAAANQAECgMIBAABNQAECgUIBAACAAAAAA==.Demonvomit:BAAANQAECgUICgAAAA==.Dernix:BAAANQADCgUIBQABNQADCgcIBwACAAAAAA==.Deroy:BAAANQADCgEIAQAAAA==.Deåth:BAAANQADCgUICAAAAA==.',
Di='Dissociative:BAAANQAECgYICAAAAA==.',
Do='Dorktard:BAAANQADCgUIBQAAAA==.Dotfeardead:BAAANQADCgYIBgAAAA==.',
Dr='Draegohl:BAAANQADCgQIBAAAAA==.Dragordawn:BAAANQABCgUIBQAAAA==.Drofiery:BAAANQAECgEIAQAAAA==.',
Ds='Dsypha:BAAANQADCgcIBwAAAA==.',
['Då']='Dåmage:BAAANQADCgcICgAAAA==.',
Ed='Edric:BAAANQADCggIEQAAAA==.Edyion:BAAANQADCgcIEgAAAA==.',
Ef='Efreet:BAAANQADCggIEwAAAA==.',
El='Elimae:BAEANQADCgIIAwAAAA==.Elvenfury:BAAANQADCggICAAAAA==.',
En='Enochian:BAAANQADCgIIAwAAAA==.',
Er='Erwinnas:BAAANQABCgEIAQAAAA==.',
Eu='Eurae:BAAANQAECgEIAQAAAA==.',
Ev='Evileye:BAAANQADCgYIBgABNQADCggICAACAAAAAA==.Evoda:BAAANQADCgcIEQAAAA==.',
Ex='Extrodinaire:BAAANQAECgEIAgAAAA==.',
Ez='Eziopandator:BAAANQABCgYICwAAAA==.',
Fa='Fadedemon:BAAANQAECgQIBQAAAA==.Faedilan:BAAANQADCgQIBAAAAA==.Farrahmoans:BAAANQAECgIIAgAAAA==.',
Fe='Fellvarg:BAAANQADCgcIDQAAAA==.Felsgoodman:BAAANQAECgcIDAAAAA==.Felstriker:BAAANQADCgYICAAAAA==.',
Fi='Filí:BAAANQADCgIIAwAAAA==.Firugan:BAAANQADCgYICgAAAA==.',
Fj='Fjaril:BAAANQADCggIFAAAAA==.',
Ga='Galroot:BAAANQADCgUICAABNQAECggIFgABAAUYAA==.Galsnipes:BAABNQAECoEWAAMBAAgJBRjMDACLAgABAAgJBRjMDACLAgADAAEJUw3cjABKAAAAAA==.Galvakrond:BAAANQADCgcIDQAAAA==.',
Ge='Geearr:BAAANQADCggIDgAAAA==.',
Gn='Gnomylanta:BAAANQADCgMIAwAAAA==.',
Go='Gomldruid:BAAANQAECggIBAAAAA==.Gomletta:BAAANQADCgcICAAAAA==.',
Gr='Grak:BAAANQAECgYIDgABNQAECgQIBAACAAAAAA==.Gratescott:BAAANQADCgIIAgAAAA==.Grik:BAAANQAECgMIBAAAAA==.Grimgull:BAAANQADCgQIBQAAAA==.',
Gw='Gwyndora:BAAANQADCggIFQAAAA==.',
['Gø']='Gøøber:BAAANQADCgUIBQAAAA==.',
Hi='Hildebrand:BAAANQADCgYIBgAAAA==.',
Ho='Holyoshyy:BAAANQAECgQIBAAAAA==.Holytiber:BAAANQADCgEIAQAAAA==.Holyvengence:BAAANQAECgQIAwAAAA==.',
Id='Idiorr:BAAANQADCgYIBgAAAA==.',
Ie='Iemanja:BAAANQADCggIDwAAAA==.',
In='Inarin:BAAANQADCgQIBAAAAA==.',
Is='Ismitethou:BAAANQADCgIIAgAAAA==.',
It='Itzsavage:BAAANQADCgQIBAAAAA==.',
Ja='Jachyra:BAAANQAECgEIAQAAAA==.Jackmanss:BAAANQADCgYICgAAAA==.Jaell:BAAANQADCgIIAwAAAA==.Jamezon:BAAANQAECgEIAQAAAA==.',
Je='Jes:BAAANQAECgMIAwAAAA==.',
Ji='Jitlok:BAAANQADCgcIEgAAAA==.',
Jo='Johnashr:BAAANQADCgQIBAABNQADCgQIBQACAAAAAA==.',
Ju='Juràssic:BAAANQAECgIIAgAAAA==.',
Ka='Kaeul:BAAANQAECgUIBgAAAA==.Kalia:BAAANQADCgEIAgAAAA==.Kalius:BAAANQADCgcIEgAAAA==.Kazgrom:BAAANQADCgQIBQAAAA==.Kazool:BAAANQADCgcICAAAAA==.',
Ke='Keanuleaves:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.',
Ki='Killerattack:BAAANQADCggIDwABNQAECgcIEAACAAAAAA==.Killerheal:BAAANQAECgcICAABNQAECgcIEAACAAAAAA==.Kiralan:BAAANQADCgEIAQAAAA==.Kizzu:BAAANQAECgIIAgAAAA==.',
Kn='Knash:BAAANQADCgEIAQAAAA==.Knower:BAAANQADCggIGwAAAA==.',
Ko='Kostah:BAAANQAECgQIBQAAAA==.',
Kr='Kracu:BAAANQADCgIIAgAAAA==.',
['Kí']='Kíli:BAAANQADCgIIAwAAAA==.',
['Kø']='Køteb:BAAANQAECgQIBgAAAA==.',
Le='Leadshot:BAAANQAECgEIAgAAAA==.',
Ma='Maakha:BAAANQADCgcIEgAAAA==.Mabalzich:BAAANQADCgQIBAAAAA==.Madsumo:BAAANQADCgcIBwABNQADCggIFAACAAAAAA==.Magroot:BAAANQAECgQIBQAAAA==.Makula:BAAANQADCgcIEAAAAA==.Mana:BAAANQAECgEIAQAAAA==.Manabun:BAAANQADCggIEAAAAA==.Manacakes:BAAANQAECgIIAgAAAA==.Manamuffins:BAAANQADCgQIBAAAAA==.Manapie:BAAANQADCgQIBAAAAA==.Mannadina:BAAANQAECgUIBwAAAA==.Mannalight:BAAANQADCgEIAQABNQAECgUIBwACAAAAAA==.Mapera:BAAANQADCgcIEgAAAA==.Marandra:BAAANQADCgIIAgAAAA==.Maray:BAAANQADCgIIAgAAAA==.Maynarde:BAAANQABCgQIBAAAAA==.',
Me='Medivarg:BAAANQADCgUIBQAAAA==.Meloncauley:BAAANQAECgYIBgAAAA==.',
Mi='Mirisa:BAAANQADCgUIBQAAAA==.Mirosa:BAAANQADCgUIBQAAAA==.',
My='Mybrother:BAAANQAECgEIAQAAAA==.',
Na='Nangsa:BAAANQADCgcIEgAAAA==.Nautisassin:BAAANQADCgcIEgABNQADCggIFAACAAAAAA==.',
Ne='Nessva:BAAANQAECgEIAQAAAA==.Neçromonger:BAAANQAECgYICAAAAA==.',
Ni='Nikidas:BAAANQADCgYIBgAAAA==.Ninurta:BAAANQADCggIDgAAAA==.',
No='Noxz:BAAANQAECgcIDAAAAA==.',
Ny='Nyiais:BAAANQADCgcIEQAAAA==.',
Ob='Obsessedwith:BAAANQADCggIFQAAAA==.',
Pa='Paladinrob:BAAANQADCgEIAgAAAA==.Palyfight:BAAANQADCgIIAgAAAA==.Pangurrban:BAAANQADCgIIAwAAAA==.',
Pe='Persiflage:BAAANQADCggIEAAAAA==.',
Po='Poinen:BAAANQADCggIDwABNQAECgQIBAACAAAAAA==.',
Pr='Priestin:BAAANQAECgEIAQAAAA==.',
Ps='Psyscape:BAAANQADCgQIBQAAAA==.',
Ra='Raginghavoc:BAAANQAECgQIBAAAAA==.Raichi:BAAANQAECgcIDAAAAA==.',
Re='Reallyreally:BAAANQAECgIIAgAAAA==.Reeally:BAAANQADCggICAABNQAECgIIAgACAAAAAA==.Reelly:BAAANQADCgUIBQABNQAECgIIAgACAAAAAA==.Reppitt:BAAANQADCgIIAgAAAA==.',
Ri='Riopia:BAAANQADCgQIBQAAAA==.',
Ro='Rod:BAAANQADCgUIBQAAAA==.Ronny:BAAANQADCgIIAgABNQAECgcIDAACAAAAAA==.Ronosaur:BAAANQAECgcIDAAAAA==.Rons:BAAANQAECgEIAQABNQAECgcIDAACAAAAAA==.Rozzinor:BAAANQADCgEIAQABNQAECgIIAgACAAAAAA==.Rozzjung:BAAANQAECgIIAgAAAA==.',
Ru='Rubyrhod:BAAANQABCgMIAwAAAA==.Rubystars:BAAANQADCggIDAABNQAECgcIBwACAAAAAA==.Ruslah:BAAANQADCggIFQAAAA==.',
Sa='Sacredmoo:BAAANQADCgIIAgABNQADCgYIBgACAAAAAA==.Sangoki:BAAANQAECgQIBQAAAA==.Sanguinius:BAAANQAECgIIAgAAAA==.Savageslayer:BAAANQAECgcIDAAAAA==.Savagespally:BAAANQADCgMIAwAAAA==.',
Se='Senshi:BAAANQADCgcIDQAAAA==.Serrena:BAAANQABCgQIBAAAAA==.Seventl:BAAANQAECgQIBAAAAA==.',
Sh='Shadowbloom:BAAANQADCgYIBgAAAA==.Shaokhan:BAAANQAECgcIEwAAAA==.Shoosts:BAAANQADCgUIBgAAAA==.Shåmwõw:BAAANQADCgYIBgAAAA==.',
Si='Simbru:BAAANQADCgcIEgAAAA==.',
Sp='Spheres:BAAANQADCgYIBgAAAA==.',
Sq='Squant:BAAANQABCgEIAQAAAA==.',
St='Stoogatz:BAAANQADCggIDQABNQAECgIIAgACAAAAAA==.Stormiee:BAAANQADCgIIAwAAAA==.Strongbow:BAAANQADCgQIBQAAAA==.',
Su='Suicidekings:BAAANQADCgUICAABNQAECgEIAQACAAAAAA==.',
Ta='Takerfan:BAAANQAECgQIBAAAAA==.Tallyblue:BAAANQAECgIIAgAAAA==.Tanarisfry:BAAANQADCgYIBgAAAA==.Taserface:BAAANQADCgIIAQAAAA==.',
Te='Temüjin:BAAANQAECgEIAQAAAA==.',
Th='Tharamore:BAAANQADCgMIAwABNQADCgYICAACAAAAAA==.Theeonlyone:BAAANQAECgQIBQAAAA==.',
Ti='Tiberlock:BAAANQADCgIIAgAAAA==.Tioshadow:BAAANQADCggIFQABNQAECgcIEwACAAAAAA==.Tiosombra:BAAANQADCggICAABNQAECgcIEwACAAAAAA==.Tiranii:BAAANQADCggIDwAAAA==.Titannus:BAAANQADCggIEwABNQADCggIFAACAAAAAA==.',
To='Tomiioka:BAAANQAECgQIBAAAAA==.',
Tr='Tralisa:BAAANQADCgEIAQAAAA==.Tribalrage:BAAANQAECgEIAQAAAA==.',
Tu='Tuktu:BAAANQAECgQIBAAAAA==.',
Va='Vandal:BAAANQAECgQIBAAAAA==.Varrigos:BAAANQADCgQIBAAAAA==.',
We='Wetbread:BAAANQAECgEIAQAAAA==.',
Wi='Wiind:BAAANQAECgcIDAAAAA==.',
Xa='Xalityr:BAAANQAECgEIAQAAAA==.Xanaxos:BAAANQADCgIIAgAAAA==.Xanis:BAAANQADCgUIDgAAAA==.',
Xh='Xhaltrix:BAAANQABCgYIBgAAAA==.',
Xo='Xonz:BAAANQAECgcIDAAAAA==.',
Xu='Xuljin:BAAANQADCgYIBwABNQAECgcIEwACAAAAAA==.',
Yo='Yomamasez:BAAANQAECgIIAgAAAA==.',
Ze='Zethieran:BAAANQADCgMIAwAAAA==.',
Zh='Zhenith:BAAANQAECgEIAQABNQADCgUIBQACAAAAAA==.',
Zi='Zirnbie:BAAANQADCgcIEgAAAA==.',
Zo='Zoub:BAAANQADCggIFAAAAA==.',
['Äc']='Ächilles:BAAANQADCgEIAQAAAA==.',
['Ða']='Ðark:BAAANQADCgEIAQABNQAECggIEAACAAAAAA==.',
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
