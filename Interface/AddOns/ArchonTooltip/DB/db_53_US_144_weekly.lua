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

local lookup = {'DemonHunter-Havoc','DemonHunter-Devourer','Unknown-Unknown','Mage-Arcane','Hunter-Survival','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Druid-Restoration','Rogue-Subtlety','DeathKnight-Unholy','Rogue-Assassination','Paladin-Retribution','Paladin-Holy','Evoker-Augmentation','Monk-Windwalker','Hunter-BeastMastery','Evoker-Devastation','Monk-Brewmaster','Priest-Holy','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','DeathKnight-Blood','Druid-Balance','Evoker-Preservation',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Account:BAAANQABCgQIBAAAAA==.',
Ag='Agnithor:BAAANQAECgYJDwAAAA==.',
Al='Aliadra:BAAANQAECgYIDQAAAA==.Alistus:BAABNQAECoEdAAMBAAgKySFaFwB3AgABAAcKSyBaFwB3AgACAAYKjSErHQAVAgAAAA==.Alphá:BAAANQADCgcICAABNQAECgUJEgADAAAAAA==.',
Am='Amyliz:BAAANQABCgcJBwAAAA==.',
An='Angua:BAAANQAECgQICQAAAA==.Anotheralt:BAAANQAECggIAQAAAA==.',
Au='Aurius:BAAANQAECgEJAQAAAA==.',
Av='Aveliandis:BAAANQAECgUIBgAAAA==.',
Az='Azerphage:BAAANQADCgQIBQABNQAECgQJBgADAAAAAA==.Azhorra:BAAANQADCgQIBwAAAA==.Azzog:BAAANQADCgcICAABNQADCgcIDgADAAAAAA==.Azül:BAAANQAECgQJBgAAAA==.',
Ba='Bacchanalian:BAAANQADCgMIAwABNQAECgQICgADAAAAAA==.Baelrin:BAAANQAECgQIBQAAAA==.Baindyn:BAAANQADCgYIFgAAAA==.Barator:BAAANQADCgYJGgAAAA==.',
Be='Beaum:BAABNQAECoEaAAIEAAgKXiX/FwBYAwAEAAgKXiX/FwBYAwAAAA==.',
Bl='Blackröse:BAABNQAECoEaAAMFAAgKvAwrBgCmAQAFAAcKDA4rBgCmAQAGAAcKawWxLQBNAQAAAA==.Bladebane:BAAANQAECgIJAgAAAA==.Blksunshine:BAAANQADCgYJFAAAAA==.',
Bo='Bolash:BAAANQAECgUIEwAAAA==.Bovinelover:BAAANQAECgYICAAAAA==.',
Br='Bradthomas:BAAANQAECgUJBgAAAA==.Bruscha:BAAANQADCggJBgAAAA==.',
Bu='Bulvhine:BAAANQAECgMIAwAAAA==.',
Ca='Cactusteeth:BAAANQAECgIIBAAAAA==.Cafeconpan:BAAANQAECgQICQAAAA==.Camford:BAAANQADCggIDgAAAA==.Cantatrix:BAAANQADCgYJDAAAAA==.Capslok:BAAANQADCggJBQAAAA==.Captinmeat:BAAANQADCgcIDwAAAA==.Castus:BAAANQADCgcIDgAAAA==.',
Ce='Cecilx:BAAANQAECgUJBgAAAA==.Censøred:BAAANQAECgIIAgAAAA==.',
Ch='Chimerax:BAABNQAECoEgAAMHAAkK2x0vCACHAQAIAAcKuRvoNABLAgAHAAUKXSAvCACHAQAAAA==.Chronic:BAAANQADCgYICgAAAA==.Chully:BAABNQAECoEYAAICAAcKjxa2HwD7AQACAAcKjxa2HwD7AQAAAA==.',
Cl='Clairíty:BAAANQAECgUJBQAAAA==.Click:BAAANQAECgUIBwAAAA==.',
Co='Comadore:BAAANQAECgcJEwAAAA==.',
Cr='Crankycad:BAAANQADCgcICgAAAA==.Credan:BAEANQAECggICAAAAA==.',
Da='Daphe:BAAANQAECgUICgAAAA==.Darknesheart:BAAANQADCgUIDQAAAA==.',
De='Deathslead:BAAANQAECgYJCgAAAA==.Decrepe:BAABNQAECoEXAAIJAAcKeBXWGADnAQAJAAcKeBXWGADnAQAAAA==.Delph:BAAANQAECgcIEgAAAA==.Deshal:BAAANQADCgUIEwAAAA==.',
Di='Discostar:BAAANQAECgYIDQAAAA==.Distill:BAAANQADCgQIBAABNQAFFAcIFQAKACgfAA==.',
Do='Dominicm:BAAANQAECgEIAQAAAA==.',
Dr='Drajhar:BAAANQADCgYIBgAAAA==.Draq:BAAANQADCgYJGgAAAA==.Druidcam:BAAANQAECgIIAgAAAA==.',
Eb='Ebonhorn:BAAANQADCgYIEgAAAA==.',
Ei='Einari:BAAANQAECgQICQAAAA==.Einark:BAAANQADCgQIBAAAAA==.',
Ek='Ekiim:BAAANQADCggIFAAAAA==.',
El='Eldamari:BAAANQADCgUJBQAAAA==.',
Em='Emdralaeth:BAAANQADCgMIAwAAAA==.Emeraldfury:BAAANQADCgUIBQAAAA==.',
Er='Eridor:BAAANQAECgMIAwAAAA==.',
Es='Esbernia:BAAANQAECgUICQAAAA==.',
Et='Ettne:BAAANQADCgYIBQAAAA==.',
Ex='Exek:BAAANQAECgQJBwAAAA==.',
Fa='Fabaztard:BAAANQAECgEIAQAAAA==.Faline:BAAANQAECgUJCQAAAA==.',
Fe='Felgetabouit:BAABNQAECoEeAAICAAgKKx5TEgCYAgACAAgKKx5TEgCYAgAAAA==.Feort:BAAANQABCgIIAgAAAA==.Ferlane:BAAANQADCgEJAQAAAA==.',
Fi='Fidelity:BAAANQABCgIIAgAAAA==.Fights:BAAANQAECgQJCAAAAA==.Filintos:BAAANQADCgMIAwAAAA==.',
Fl='Fleshworker:BAAANQADCgYIBgAAAA==.',
Fo='Fontaine:BAAANQADCgUICAAAAA==.Foradin:BAAANQAECgUICQAAAA==.Forky:BAAANQAECgEJAwAAAA==.Foxknight:BAAANQADCgYIEQAAAA==.',
Fr='Franksnbeans:BAAANQAECgIIAgAAAA==.Fryeren:BAAANQADCggJBwAAAA==.',
['Fí']='Fírefox:BAAANQADCgUJBQABNQADCgYIEQADAAAAAA==.',
Ga='Gaern:BAABNQAECoEbAAILAAgKcBjWIABdAgALAAgKcBjWIABdAgAAAA==.Gaidan:BAAANQABCgMIAgABNQAECgkJGAACAGgVAA==.Gaidin:BAABNQAECoEYAAICAAkKaBX1EwCDAgACAAkKaBX1EwCDAgAAAA==.Gameslayer:BAAANQAECgEIAQAAAA==.Gankzilla:BAABNQAECoEeAAIMAAgKRBa7EwBgAgAMAAgKRBa7EwBgAgAAAA==.',
Gi='Gila:BAAANQADCgcJCAAAAA==.Gizzle:BAABNQAECoEeAAINAAgKgxX0SwAkAgANAAgKgxX0SwAkAgAAAA==.',
Gr='Greel:BAAANQABCgEIAQAAAA==.Grimanack:BAAANQADCgYJDwAAAA==.Grændal:BAAANQADCgQIBAABNQAECgkJGAACAGgVAA==.Grÿm:BAAANQADCgYIBwAAAA==.',
Ha='Hanjha:BAAANQAECgUIBgAAAA==.',
He='Helldozer:BAAANQAECgUIBwAAAA==.Hexinu:BAAANQAECgUIBwAAAA==.',
Hi='Hiyue:BAAANQAECggJAgAAAA==.',
Ho='Holeinheart:BAAANQADCgMIAwAAAA==.',
Hu='Hugzy:BAAANQADCgYICQAAAA==.',
Hy='Hypnocide:BAEANQAECgQICAAAAA==.',
Ib='Ibuki:BAAANQADCgIIAgABNQAECggJHgAOABwFAA==.',
Ig='Iguanajon:BAAANQAECgQIBwAAAA==.',
Im='Impsane:BAAANQADCgcICQAAAA==.',
Ir='Irv:BAAANQAECgQIAgAAAA==.',
Is='Isellrocks:BAAANQAECgYJCAAAAA==.',
Ja='Jaxxa:BAAANQADCggIDgAAAA==.',
Je='Jeddiah:BAAANQAECgEJAQAAAA==.Jetstorm:BAAANQAECgYIBgAAAA==.',
Ji='Jinkès:BAAANQAECgIIAgAAAA==.',
Ju='Juanting:BAAANQADCgEJAgAAAA==.Jubei:BAAANQAECggJEgAAAA==.Judis:BAAANQAECgUIDAAAAA==.Justokevoker:BAABNQAECoEYAAIPAAcKARzhBAA1AgAPAAcKARzhBAA1AgAAAA==.',
Ka='Kainda:BAAANQABCgIIAgAAAA==.Kairì:BAAANQAECgMJBAAAAA==.Kalifist:BAABNQAECoEeAAIQAAkKthxlCAAIAwAQAAkKthxlCAAIAwAAAA==.Kalku:BAAANQADCggJGQAAAA==.Kanajotoma:BAAANQADCgYIEQAAAA==.Karlai:BAAANQADCggIFAABNQAECgkJGAACAGgVAA==.',
Ke='Keldrune:BAAANQADCgQJBAAAAA==.Keleena:BAEANQAECgQICQAAAA==.Keze:BAABNQAECoEYAAIRAAcKBx6HNgBaAgARAAcKBx6HNgBaAgAAAA==.',
Kh='Khorahlia:BAAANQADCgQIBAABNQAECggJGwALAHAYAA==.',
Ki='Killzshot:BAAANQADCgQIBAAAAA==.Kinst:BAAANQAECgQICQAAAA==.Kitanyia:BAAANQAECgcJEQAAAA==.Kittiy:BAAANQAECgEIAQAAAA==.Kizahnevo:BAAANQADCggIHgAAAA==.',
Ko='Kordelia:BAAANQAECgQJCAABNQAECggJGwALAHAYAA==.',
Kr='Krench:BAAANQADCgQIBAAAAA==.Krusty:BAAANQADCgYIBgAAAA==.',
Ky='Kyakuna:BAAANQADCgQJBAAAAA==.Kyloon:BAAANQAECgQIBwAAAA==.Kyrah:BAAANQAECgQICQAAAA==.',
La='Lakatryna:BAAANQAECgUJBQABNQAFFAQJBwAGAIoZAA==.Lamanira:BAAANQADCgYJFAAAAA==.',
Le='Lejend:BAAANQAECgQJCAAAAA==.',
Li='Lithis:BAAANQADCgcIBwAAAA==.',
Ll='Llamakiller:BAAANQADCgEIAQABNQADCgUJCwADAAAAAA==.Llanedh:BAAANQAECgIJAgAAAA==.',
Lo='Loaganic:BAAANQADCggICAAAAA==.Lonelyhearts:BAAANQAECgEIAgAAAA==.Lorimuni:BAAANQADCggIFAAAAA==.',
Ly='Lytol:BAAANQAECgUIBgAAAA==.',
Ma='Maenad:BAAANQAECgQICgAAAA==.Maeple:BAAANQADCgcIDgAAAA==.Manamontana:BAAANQAECgMIAwAAAA==.Mazikeene:BAAANQADCgYIBgAAAA==.',
Me='Meladyn:BAAANQAECgYIEgAAAA==.',
Mi='Miami:BAACNQAFFIEOAAISAAUKDxuKAQDJAQASAAUKDxuKAQDJAQA1AAQKgRoAAhIACQoOJCQCAH8DABIACQoOJCQCAH8DAAAA.Michelle:BAAANQADCgEIAQAAAA==.Missmaam:BAAANQADCgcIDAAAAA==.Mistroot:BAAANQADCgcICgAAAA==.Mizu:BAAANQADCgUIBQAAAA==.',
Mo='Monkfox:BAABNQAECoEaAAITAAkKeCKbAgBEAwATAAkKeCKbAgBEAwABNQAECgcIGAATAPQjAA==.Moon:BAAANQADCgUIBQAAAA==.Moonfirespam:BAAANQADCggICAAAAA==.',
Mu='Mushuwoonter:BAAANQAECgQIBAABNQAECgcIFgAPABYTAA==.Muztang:BAAANQAECgQIBQAAAA==.',
My='Mythhunter:BAAANQAECgEIAQAAAA==.',
['Mô']='Mônkii:BAABNQAECoEYAAITAAcK9CPuBAC/AgATAAcK9CPuBAC/AgAAAA==.',
Na='Nace:BAAANQABCgIIAgAAAA==.Naenia:BAAANQADCgcIDAAAAA==.Nariar:BAAANQADCggICQABNQAECggJHgAOABwFAA==.Nateldin:BAAANQAECgUIDAAAAA==.',
Ni='Nightcat:BAAANQADCgUICQAAAA==.Niisha:BAAANQAECgUICgABNQAECgcIEQADAAAAAA==.',
No='Nocainus:BAAANQAECgUIBwAAAA==.',
['Nø']='Nøtsure:BAAANQAECgEJAgABNQAECgIIAgADAAAAAA==.',
Ob='Obsidia:BAAANQAECgUIBwAAAA==.',
Od='Oddlife:BAAANQAECgYIDAAAAA==.',
Oh='Ohsnapkatt:BAAANQADCgUJBQAAAA==.',
Om='Omari:BAAANQADCgYJBgAAAA==.',
On='Onceathief:BAAANQADCgQJBAAAAA==.Onik:BAAANQADCgIIAwABNQADCgUJCwADAAAAAA==.',
Op='Ophj:BAABNQAECoEhAAIEAAkKahwQQwDCAgAEAAkKahwQQwDCAgAAAA==.',
Or='Orangejulius:BAAANQADCgYICwABNQADCggIFAADAAAAAA==.Orangutan:BAAANQAECgMIBQAAAA==.Orinoheal:BAAANQADCgYICAAAAA==.',
Os='Oskar:BAAANQAECgcIEwAAAA==.',
Pa='Pallycam:BAAANQADCgcIBwAAAA==.',
Pe='Pebda:BAAANQADCgYIEgAAAA==.Pebde:BAAANQADCgYIBgAAAA==.Perilous:BAAANQADCgYIEgAAAA==.',
Ph='Phoelar:BAAANQAECgMIBgAAAA==.Phuumyn:BAAANQAECgUIBwAAAA==.',
Pi='Piccoblast:BAACNQAFFIEJAAIEAAUKkA08DACcAQAEAAUKkA08DACcAQA1AAQKgSEAAgQACQr8JLINAIoDAAQACQr8JLINAIoDAAAA.Pichus:BAAANQAECgQIBAABNQAECgUJEgADAAAAAA==.Picklesoup:BAAANQAECgIIAgAAAA==.Piickles:BAAANQAFFAIIBAAAAA==.Pippopper:BAAANQAECgIIAgABNQAECggJHQABAMkhAA==.Pity:BAAANQAECgEIAgAAAA==.',
Pl='Plutø:BAAANQAECgUICAAAAA==.',
Po='Polylocks:BAAANQADCgYICwABNQADCgcIBwADAAAAAA==.Potatogg:BAAANQAECgEIAQAAAA==.',
Pr='Praeastra:BAEANQAECgYJCwAAAA==.Prókill:BAAANQAECgQIBQAAAA==.',
Ps='Psychokitty:BAAANQAECgUJDwAAAA==.',
Qu='Quilian:BAABNQAECoEdAAIUAAgKhCJgDQAVAwAUAAgKhCJgDQAVAwAAAA==.',
Ra='Raelynn:BAAANQAECgUIBwAAAA==.Rancier:BAAANQADCgYJGgAAAA==.Rashalisk:BAAANQADCgMIAwAAAA==.',
Re='Rednecker:BAAANQABCgIIAgAAAA==.Redvex:BAABNQAECoEYAAMIAAcKvCNSGwDEAgAIAAcKvCNSGwDEAgAVAAEKRyNiVQBaAAAAAA==.Reinhard:BAAANQAECgEJAgAAAA==.Rencraw:BAAANQADCgYIEAAAAA==.Renras:BAAANQADCggJEwAAAA==.',
Rh='Rhain:BAAANQAECgYICgAAAA==.Rhuxy:BAAANQAECgEIAQAAAA==.',
Ri='Rinah:BAABNQAECoEYAAMKAAgKyxVHEABFAgAKAAgKyxVHEABFAgAMAAIK9Q0KUQB/AAAAAA==.',
Ro='Ronwen:BAAANQADCgUIBQABNQAECggJHgAOABwFAA==.Rootbeard:BAAANQAECgUJBgAAAA==.Rosanna:BAAANQADCgUIEgAAAA==.Rotyr:BAAANQADCggIFQAAAA==.',
Ru='Ruana:BAEANQADCgYIFQAAAA==.Rubberlip:BAAANQAECgQJBAAAAA==.',
Ry='Rye:BAAANQAECgIIAwAAAA==.',
Sc='Scoobey:BAAANQAECgEJAgAAAA==.Scots:BAAANQABCgcJDwAAAA==.Scubbs:BAABNQAECoEeAAIWAAgKkBsBIgCIAgAWAAgKkBsBIgCIAgAAAA==.Scubbsboo:BAAANQADCggJCQABNQAECggJHgAWAJAbAA==.',
Se='Selenei:BAAANQADCgEIAQAAAA==.Servantes:BAAANQAECgUIBgAAAA==.',
Sh='Shamancam:BAAANQAECgMIAwAAAA==.Shamp:BAAANQADCggJGwAAAA==.Shiggy:BAAANQAECgUIBwAAAA==.Shotya:BAAANQAECgQIBgAAAA==.',
Si='Sixthknight:BAAANQADCggIGgAAAA==.',
Sl='Slappi:BAAANQAECgIJAgAAAA==.',
Sn='Snarkypony:BAAANQADCgYJFgAAAA==.',
So='Sonofathorck:BAAANQADCgEIAQAAAA==.Sorsere:BAAANQADCgcIBwAAAA==.',
Sp='Spcecialk:BAAANQADCggJCQAAAA==.Specialk:BAABNQAECoEYAAIXAAcKRxEBSADTAQAXAAcKRxEBSADTAQAAAA==.Spellthat:BAAANQADCggJCAAAAA==.',
St='Stirredihime:BAAANQAECgUICAAAAA==.Stormmage:BAAANQAECgMIAwABNQAECgkJHgAYAE8gAA==.',
Su='Sugarmomma:BAAANQADCgcIBwAAAA==.Sulph:BAAANQAECgUIBwAAAA==.Sundorei:BAAANQADCgYICAAAAA==.',
Sv='Svalir:BAAANQADCgUJCwAAAA==.',
Ta='Talshekar:BAAANQAECgIIAgAAAA==.Tarsis:BAAANQAECgIIAwAAAA==.',
Te='Teiana:BAABNQAECoEXAAINAAgKghyHOgBqAgANAAgKghyHOgBqAgAAAA==.',
Th='Thaevin:BAAANQAECgQICAAAAA==.Thews:BAAANQABCgEIAQAAAA==.Thilendrel:BAAANQAECgcIEwAAAA==.Thingwan:BAABNQAECoEeAAIJAAgKCCElBwAFAwAJAAgKCCElBwAFAwAAAA==.Thunderman:BAAANQAECgQICgAAAA==.',
Ti='Tinystink:BAAANQAECgMJBwAAAA==.',
To='Toddstephens:BAAANQADCgYICgAAAA==.Tors:BAABNQAECoEYAAMZAAgK6Qw8OwCYAQAZAAcKpg08OwCYAQAJAAIK3AReQwBlAAAAAA==.Toterbonem:BAAANQADCgMIAwAAAA==.Toyotathon:BAAANQADCgYIBgABNQADCggIFAADAAAAAA==.',
Tr='Trasky:BAAANQAECgQICQAAAA==.Trollololo:BAAANQAECgUIBwAAAA==.Troy:BAAANQAECgUJCQAAAA==.Trylly:BAAANQADCgcIBwAAAA==.Trëze:BAAANQAECggIDgAAAA==.',
Tt='Ttaartt:BAABNQAECoEZAAIaAAkKgQ95EQA+AgAaAAkKgQ95EQA+AgAAAA==.',
Ty='Typh:BAABNQAECoEaAAIMAAkKPCEbAwB3AwAMAAkKPCEbAwB3AwAAAA==.',
Un='Undeaddemon:BAAANQAECgcIEgAAAA==.Undeaddh:BAAANQADCggICAABNQAECgcIEgADAAAAAA==.Undignified:BAAANQAECgQJBgAAAA==.Unholysixth:BAAANQADCgUIEwAAAA==.',
Va='Vanidarr:BAAANQADCgQIBAAAAA==.',
Ve='Verasia:BAAANQADCgYJCQAAAA==.',
Vi='Vidikan:BAAANQADCgIIAwAAAA==.Violett:BAAANQAECgYJDwAAAA==.',
Vo='Voidwarranty:BAAANQAECgUJEgAAAA==.Vortre:BAAANQABCgcIBwAAAA==.',
Vv='Vvumpscut:BAAANQAECgcIEgAAAA==.',
Wa='Waldón:BAAANQAECgIIAgAAAA==.',
Wi='Wildsoul:BAAANQAECgEIAQAAAA==.Wistywind:BAAANQABCggJCwAAAA==.',
Xc='Xclaw:BAAANQAECgQJBAAAAA==.',
Xe='Xeroxgravity:BAAANQAECgIIAwAAAA==.Xeroxshaman:BAAANQADCgQJAgAAAA==.',
Xi='Xilphira:BAAANQADCgUIDwAAAA==.Xirian:BAAANQAECgEJAQAAAA==.',
Xl='Xlithz:BAAANQAECgUJCQAAAA==.',
Ya='Yah:BAAANQADCgQIBwAAAA==.Yautjah:BAAANQADCgUIBQAAAA==.',
Yl='Ylene:BAAANQADCgUICgAAAA==.',
Yo='Yoink:BAABNQAECoEaAAILAAgKfB+3FADJAgALAAgKfB+3FADJAgAAAA==.Yondu:BAAANQADCgYIBwABNQAECgUJBgADAAAAAA==.',
Za='Zalzuke:BAAANQAECgEJAQAAAA==.Zarinchaos:BAAANQAECgUJCwAAAA==.',
Ze='Zein:BAAANQADCgYJGgAAAA==.Zente:BAABNQAECoEdAAIRAAgKfQ4mTQALAgARAAgKfQ4mTQALAgAAAA==.Zequill:BAAANQAECgQJCAAAAA==.Zevfury:BAAANQADCgIJAgABNQAECggIGAARABYhAA==.Zevsticles:BAABNQAECoEYAAIRAAgKFiE1HwDBAgARAAgKFiE1HwDBAgAAAA==.',
Zh='Zhom:BAACNQAFFIEHAAIGAAQKihmaBwBQAQAGAAQKihmaBwBQAQA1AAQKgSQAAgYACQoDIlIHADQDAAYACQoDIlIHADQDAAAA.',
Zo='Zooj:BAAANQAECgUIBgAAAA==.Zorlak:BAAANQAECgEIAgAAAA==.',
Zu='Zulall:BAAANQADCggIDAAAAA==.',
Zy='Zylofeather:BAAANQADCgUIBQAAAA==.',
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
