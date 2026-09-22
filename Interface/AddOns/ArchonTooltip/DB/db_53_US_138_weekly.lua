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

local lookup = {'Unknown-Unknown','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Mage-Frost','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Restoration','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Priest-Discipline','Priest-Shadow','Rogue-Subtlety','Paladin-Holy','Warlock-Affliction','Shaman-Enhancement','Shaman-Elemental','Paladin-Retribution','DemonHunter-Vengeance','Priest-Holy','Paladin-Protection','Druid-Balance','Druid-Restoration',}
local provider = {region='US',realm='KulTiras',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aarix:BAAANQAECgUIDAAAAA==.',
Ae='Aendillan:BAAANQADCgUIBQAAAA==.',
Af='Affonasei:BAAANQAECgQICQAAAA==.',
Ag='Agkistrodon:BAAANQADCgUIBQABNQAECgUJDAABAAAAAA==.',
Ai='Aicaramba:BAAANQAECgYIBwAAAA==.Aileen:BAAANQADCgQIAgAAAA==.',
Aj='Ajay:BAAANQADCggICAAAAA==.',
Ak='Akashi:BAAANQAECgMIAwABNQAECgkJJgACAK8cAA==.',
Al='Alacrodie:BAAANQADCgQICAAAAA==.',
Am='Amoonsi:BAAANQADCgMIAwABNQAECgQIBwABAAAAAA==.',
An='Angrytotems:BAAANQAECgQJBAABNQAECgYJCQABAAAAAA==.Annaborshen:BAAANQABCgIIAgAAAA==.Antoccino:BAAANQAECgQIBQAAAA==.',
Ar='Aragorno:BAAANQAECgIIBQAAAA==.Arcturen:BAAANQAECgIIAgAAAA==.Ardala:BAAANQABCgIIAgAAAA==.Arenthal:BAAANQAECgQICAABNQAECggJGwADACsdAA==.',
As='Ashalana:BAAANQADCgUIBQAAAA==.Asheby:BAAANQADCgMIAwABNQAECgQIBQABAAAAAA==.Ashiera:BAAANQAECgUICwAAAA==.Astralmorph:BAAANQADCgYIBgAAAA==.',
At='Atomic:BAAANQAECgEIAQAAAA==.',
Az='Azylstrid:BAAANQADCgYIDAAAAA==.',
Ba='Baeu:BAAANQABCgUIBwAAAA==.Balentine:BAAANQAECgUICQAAAA==.Banostraza:BAAANQAECgQIBQAAAA==.Baspir:BAAANQAECgcJEQAAAA==.',
Be='Beeboop:BAAANQABCgYIEAAAAA==.Belly:BAAANQAECgYIEwAAAA==.Belrae:BAAANQADCggIDQAAAA==.Benchfresh:BAAANQAECggIDAAAAA==.Bendah:BAAANQAECgEIAQAAAA==.Bender:BAAANQADCgYIBgAAAA==.Bezieck:BAAANQADCgYJDwAAAA==.',
Bi='Bigfolks:BAAANQADCgUIBgAAAA==.Bigollock:BAAANQADCgYICwAAAA==.Bili:BAAANQADCgYIBgAAAA==.',
Bl='Bloodarrow:BAAANQADCgUJBgAAAA==.Bloodbound:BAAANQADCgYIBgAAAA==.',
Bo='Bockchi:BAAANQAECgQJBQAAAA==.Bonanas:BAAANQABCgMJAwAAAA==.Bonegavel:BAAANQABCgQIBgAAAA==.Bookhuntress:BAAANQAECgUIBQAAAA==.',
Br='Branex:BAAANQADCggICAAAAA==.Branpaw:BAAANQADCgMIAwAAAA==.Brewdeez:BAAANQAECgYIEQAAAA==.Brewzen:BAAANQADCgYIBgAAAA==.Brewzer:BAABNQAECoEXAAIEAAgK+AstFQChAQAEAAgK+AstFQChAQAAAA==.Brick:BAAANQADCgQIBAAAAA==.Brint:BAAANQADCgQIBAAAAA==.Bronad:BAABNQAECoErAAMDAAkKRCb7AQDkAwADAAkKRCb7AQDkAwAFAAEKPx9PKwBDAAAAAA==.Broomhandle:BAAANQAECgQJCQAAAA==.',
Bu='Bumbushka:BAAANQAECgYICgAAAA==.Burinn:BAAANQAECgIIAgABNQAECgUIDAABAAAAAA==.',
Ca='Caeus:BAAANQAECgQJBQAAAA==.Cam:BAAANQAECgYIEQAAAA==.Carolinabele:BAAANQADCggICAAAAA==.Cauud:BAAANQADCgUJCQAAAA==.',
Cb='Cbd:BAAANQADCgcIEwAAAA==.',
Ce='Celerious:BAAANQABCgIIAgAAAA==.',
Ch='Chacruna:BAAANQAECgMIBQAAAA==.Chelan:BAAANQAECgUIDAAAAA==.Chloelock:BAAANQABCgEJAQAAAA==.Chronicler:BAAANQADCgEIAQAAAA==.Chuntspeed:BAAANQABCgYJCwAAAA==.Chuye:BAAANQAECgEJAQABNQAECgUJCgABAAAAAA==.',
Cl='Clambulance:BAABNQAECoEZAAIGAAgKThguLwB3AgAGAAgKThguLwB3AgAAAA==.',
Cn='Cnova:BAAANQAECgQIBAAAAA==.',
Co='Codythedead:BAABNQAECoEgAAIHAAkKOx+lDAAiAwAHAAkKOx+lDAAiAwAAAA==.Coraf:BAABNQAECoEdAAIIAAkK2iAACQBLAwAIAAkK2iAACQBLAwAAAA==.Coyotl:BAAANQADCggIEAAAAA==.',
Cu='Cuvier:BAAANQADCggJFgAAAA==.',
Da='Danak:BAAANQADCgIJBQAAAA==.',
De='Deadlyfrosty:BAAANQADCgUIBwAAAA==.Deathmob:BAAANQAECgQJCAAAAA==.Deathsynth:BAAANQADCgQJBAABNQAECgQJCAABAAAAAA==.Debixie:BAABNQAECoEYAAMCAAgK6Rp7DwCYAgACAAgK6Rp7DwCYAgAJAAYKuBMYCgCLAQAAAA==.Decisive:BAAANQADCgYIBgABNQAFFAcIEgAKALEfAA==.Dejection:BAAANQABCgYIBwAAAA==.Demisi:BAAANQAECgQIBgAAAA==.Demiurge:BAAANQAECgYJDgAAAA==.',
Di='Diasundra:BAAANQAECgUIDwAAAA==.Dibbons:BAAANQAECgYIBwAAAA==.Divinatjin:BAAANQADCgYICQAAAA==.',
Do='Dollars:BAAANQAECgIIAgABNQAECgMIBQABAAAAAA==.Dottingyou:BAABNQAECoEfAAMLAAkKVx4bEgDKAQAKAAcKqx2CNQBIAgALAAYKIhobEgDKAQAAAA==.',
Dr='Dracthyrbm:BAAANQADCgYJFAAAAA==.Dreepy:BAAANQAECgUJBQAAAA==.Drransom:BAAANQADCgEIAQAAAA==.Dryan:BAAANQAECgQIBQAAAA==.',
Du='Duo:BAAANQAECgYIEQAAAA==.Duragon:BAAANQAECgYIDgAAAA==.',
Ei='Eipwoc:BAAANQADCggIBwAAAA==.',
El='Elciere:BAAANQADCggJDAAAAA==.Eloreith:BAAANQAECgUICwAAAA==.',
Em='Emamagee:BAAANQADCgQIBgAAAA==.Emilia:BAAANQAECgUJDgAAAA==.',
En='Endressa:BAABNQAECoEYAAIMAAcKCRJgBgDLAQAMAAcKCRJgBgDLAQAAAA==.',
Er='Eralendryn:BAAANQADCgEIAQAAAA==.Erelios:BAAANQAECgQJBQAAAA==.',
Es='Eski:BAABNQAECoEWAAIJAAgKyRccBQBfAgAJAAgKyRccBQBfAgAAAA==.Essaena:BAAANQAECgUIDAAAAA==.',
Eu='Eura:BAAANQADCgEJAQAAAA==.Eureka:BAEANQAECgYIEAAAAA==.',
Fa='Faddeyshnek:BAAANQAECgYIEwAAAA==.Fatgirljuice:BAAANQAECgMICAABNQAECggIDgABAAAAAA==.',
Fe='Felysambre:BAAANQAECgEJAQAAAA==.',
Fi='Fish:BAACNQAFFIEVAAINAAcKXiQnAADwAgANAAcKXiQnAADwAgA1AAQKgSQAAg0ACQrJJkMAAPsDAA0ACQrJJkMAAPsDAAAA.',
Fl='Flight:BAABNQAECoEmAAMCAAkKrxzBDwCTAgACAAgK3xvBDwCTAgAOAAYKURZQGQDUAQAAAA==.Floofee:BAAANQADCgQIBAAAAA==.',
Fo='Footfinger:BAAANQABCgUIBgAAAA==.Forsynth:BAAANQAECgQJCAAAAA==.',
Fu='Fubar:BAAANQADCgYIBgAAAA==.',
Ga='Ganniy:BAAANQABCgEJAQAAAA==.',
Ge='Gewitt:BAAANQAECgQJBgAAAA==.',
Go='Gonjah:BAAANQAECgEJAQAAAA==.',
Gr='Grabomage:BAAANQAECgQIBAABNQAECgkJKwADAEQmAA==.Grabovoker:BAAANQADCgIIAgABNQAECgkJKwADAEQmAA==.Grazienne:BAAANQADCgQIBwAAAA==.Greavos:BAAANQAECgQICQAAAA==.Griggus:BAAANQAECgIIBAAAAA==.Grimgar:BAAANQAECgQICQAAAA==.Grimmshady:BAAANQADCgQJBgAAAA==.',
Gu='Gumbles:BAAANQAECgUJCgAAAA==.Gurney:BAAANQAECgYICQAAAA==.Guzprimal:BAAANQAECgEIAQAAAA==.',
Gw='Gwenory:BAAANQABCgQIBAAAAA==.',
Gy='Gying:BAAANQAECgIJAgAAAA==.',
Ha='Hanekawa:BAAANQAECgQIBgABNQAECgkJIQAFAL0kAA==.Hannie:BAAANQADCgIJBgAAAA==.',
He='Headhúnter:BAAANQAECgYICAAAAA==.Heartsparx:BAAANQAECgUJDQAAAA==.Heatseeka:BAAANQAECgYIDQAAAA==.Hexxiz:BAAANQAECgQIBAABNQAECgYIDwABAAAAAA==.',
Hi='Hiphopinator:BAAANQAECgQICQAAAA==.',
Ho='Ho:BAAANQADCgQIBAAAAA==.Holyshock:BAABNQAECoEgAAIPAAgKcBf+LQBJAgAPAAgKcBf+LQBJAgAAAA==.Holyterror:BAAANQADCgQICAAAAA==.',
Ia='Ianthe:BAAANQAECgIJAgAAAA==.',
Ib='Iboga:BAAANQAECgQICQAAAA==.Ibrahimovic:BAAANQADCggIEQAAAA==.',
Ig='Ignitecro:BAAANQABCgcIDwAAAA==.Igram:BAAANQAECgIJAwAAAA==.',
Il='Illumona:BAAANQAECgIIAgAAAA==.Iluz:BAAANQADCgMIAwAAAA==.',
In='Inafume:BAAANQADCggJEwAAAA==.Inoxia:BAAANQAECgMJCAAAAA==.Intrépidice:BAAANQAECgMJBgAAAA==.',
Ix='Ixtabay:BAABNQAECoEgAAQQAAkKnR3rAQDMAgAQAAkKexvrAQDMAgALAAMK3Bc0MQDcAAAKAAMKvQ3XuACxAAAAAA==.',
Ja='Jamurra:BAAANQAECgIIBAAAAA==.Jaylinn:BAAANQAECgYIEQAAAA==.Jazzmend:BAAANQAECgQJBAAAAA==.',
Je='Jeanne:BAAANQAECgYIDAAAAA==.Jellykins:BAAANQAECgQIBQAAAA==.',
Ji='Jimjamjuju:BAAANQAECgQICAAAAA==.Jimsonweed:BAAANQAECgQICgAAAA==.',
Jo='Josie:BAAANQAECgUIBwAAAA==.Jozbirt:BAAANQAECgcJEwAAAA==.',
Ka='Kaeiria:BAAANQADCgQIBAAAAA==.Kael:BAAANQAECgQICQAAAA==.Kalaanri:BAAANQAECgIJAgAAAA==.Kalyandra:BAAANQAECgQIBAAAAA==.Karlach:BAAANQADCgUIBQABNQAECgUJDQABAAAAAA==.Karumie:BAAANQAECgUIDgAAAA==.Kateera:BAAANQADCgQIBAAAAA==.',
Ke='Keden:BAAANQADCgQIBgAAAA==.Kelesa:BAAANQAECgEIAQAAAA==.Keljaden:BAAANQAECgUICAAAAA==.',
Kh='Kheyra:BAAANQAECgUJDAAAAA==.',
Ki='Kirsha:BAAANQADCggJCAABNQAECgIIBAABAAAAAA==.Kittybeef:BAAANQABCgIIAgAAAA==.Kiwiiga:BAAANQAECgIIAwAAAA==.',
Kn='Knoxxic:BAAANQADCgMJBAAAAA==.',
Ko='Kohnor:BAAANQADCgQICAAAAA==.Koopalizard:BAAANQAECgQIBwAAAA==.Kopi:BAAANQAECgQIBAABNQAECgQIBQABAAAAAA==.Korlatt:BAAANQAECgUIBQAAAA==.Kowalabear:BAAANQAECgEIAQAAAA==.',
Ku='Kuaha:BAAANQADCgYIBgABNQADCgQIBAABAAAAAA==.Kupa:BAAANQADCgYJBwAAAA==.Kurom:BAAANQADCgcJDQAAAA==.Kurston:BAAANQAECgUIDAAAAA==.',
Ky='Ky:BAAANQADCgEIAQAAAA==.',
['Kã']='Kãtniss:BAAANQADCgQIBwAAAA==.',
La='Labella:BAAANQADCgQIBAAAAA==.Lacia:BAAANQADCgYIBgABNQAECgYJCQABAAAAAA==.Laih:BAAANQAECgEIAQAAAA==.Landsong:BAAANQADCgQIBAAAAA==.',
Le='Leyote:BAAANQAECgQICQAAAA==.',
Li='Liady:BAAANQADCgEJAQAAAA==.Lightshop:BAAANQADCgYJBgAAAA==.Liirah:BAAANQADCgIJAgAAAA==.Lilyfox:BAAANQAECgQJBAAAAA==.Lindithrial:BAAANQABCgQIBAAAAA==.Livingdead:BAAANQADCggIGQAAAA==.',
Lo='Lorianne:BAAANQADCggJEAAAAA==.Lorraine:BAAANQADCgQIBAAAAA==.Lowdangle:BAAANQADCgcIBwAAAA==.',
Lu='Luucifur:BAAANQABCgMIAwAAAA==.',
Ma='Mackpumpkin:BAAANQAECgIIAgAAAA==.Macktheknife:BAAANQADCgQICAABNQAECgkJIAAQAJ0dAA==.Madalyn:BAAANQADCgEIAQAAAA==.Magdelyne:BAAANQAECggJAQAAAA==.Makklehaney:BAAANQAECgQICAAAAA==.Mallaah:BAAANQADCgUIBQAAAA==.Marovingian:BAAANQAECgQJCAAAAA==.Matthad:BAAANQAECgQJBQAAAA==.',
Mc='Mcnastie:BAAANQAECgQIBgAAAA==.Mcsluts:BAAANQADCgYJCwAAAA==.',
Me='Melmirict:BAAANQADCgMJAwAAAA==.Merciala:BAAANQAECgUICgAAAA==.',
Mi='Milyyanna:BAAANQADCgMIBwAAAA==.Mirilla:BAAANQAECgYJDAAAAA==.',
Mo='Moddoxx:BAAANQAECgQICQAAAA==.Mohawk:BAAANQAECgMIAwAAAA==.Molen:BAAANQAECgEIAQAAAA==.Mommyjuice:BAAANQAECggIDgAAAA==.Monkle:BAAANQAECgYJDQAAAA==.Monohan:BAAANQADCgUIBQABNQAECgQJCAABAAAAAA==.Moonsii:BAAANQAECgQIBwAAAA==.Mooroth:BAAANQAECgUICgAAAA==.Morkilro:BAAANQABCgIJAgAAAA==.Morozko:BAAANQADCgQIBAAAAA==.',
Mu='Muddler:BAAANQAECgIIAgAAAA==.Murinn:BAAANQAECgUJCQAAAA==.',
['Mà']='Màggles:BAAANQAECgIJAwAAAA==.',
Na='Nadd:BAAANQAECgIJAgAAAA==.Naledi:BAAANQADCggIDQAAAA==.Naralyn:BAABNQAECoEXAAMRAAgKjBQaDQAqAgARAAgKyxEaDQAqAgASAAUKwRFgcQBAAQAAAA==.',
Ne='Negrido:BAAANQAECgYIEQAAAA==.Nei:BAAANQAECgQICAAAAA==.Neon:BAAANQADCgUICQAAAA==.',
Ni='Nikem:BAAANQAECgIIAgAAAA==.',
No='Noelle:BAAANQAECgUIBgAAAA==.Norelei:BAAANQADCgQJBAABNQAECgUJDAABAAAAAA==.Noriyuki:BAAANQAECgMIBQAAAA==.',
Ny='Nyxahlia:BAAANQADCgUIBgAAAA==.',
Og='Oghom:BAAANQADCggICAAAAA==.Ogrekin:BAAANQAECgQIBAAAAA==.',
Ol='Olderon:BAAANQAECgQIBQAAAA==.Olrong:BAAANQAECgQICQAAAA==.Oluja:BAAANQAECgMIBgAAAA==.',
On='Onuris:BAAANQABCgYJCAAAAA==.',
Op='Opacuslupus:BAAANQAECgEJAQAAAA==.Oppressin:BAAANQAECgQJCAAAAA==.',
Os='Oshunn:BAABNQAECoEaAAIDAAgKoxDziwD5AQADAAgKoxDziwD5AQAAAA==.Oshìe:BAABNQAECoEXAAIPAAgKIR9uFgDZAgAPAAgKIR9uFgDZAgAAAA==.Osroes:BAAANQAECgQIEgAAAA==.',
Ov='Overdoom:BAAANQAECgYIEQAAAA==.Ovscur:BAAANQAECgUIDwAAAA==.',
Pa='Paladinjohn:BAABNQAECoEgAAITAAkKZiXxBwCbAwATAAkKZiXxBwCbAwAAAA==.Palykat:BAAANQAECgIJAgAAAA==.Papiroflz:BAAANQAECgYIEQAAAA==.',
Pe='Pennywisé:BAAANQAECgYIDQAAAA==.Pesttilence:BAAANQABCgYIDAAAAA==.',
Pl='Plaguegying:BAAANQAECgQICQABNQAECgIJAgABAAAAAA==.Ploofee:BAAANQAECgEJAQAAAA==.',
Pr='Progresz:BAAANQAECgEIAQAAAA==.',
Pu='Purebread:BAAANQADCgUIBQAAAA==.',
Py='Pykel:BAAANQAECgUIDwAAAA==.',
Qa='Qaren:BAAANQADCgUJCQAAAA==.',
Ra='Raishun:BAAANQAECgEJAQAAAA==.Raizo:BAAANQAECgEIAQAAAA==.Rake:BAAANQAECgYIEQAAAA==.Rannï:BAAANQADCgEIAQABNQAECgkJIAAQAJ0dAA==.Raskreia:BAAANQAECgYIBgABNQAECgkJIQAFAL0kAA==.Rassina:BAAANQADCgEIAQAAAA==.Rawk:BAAANQADCgYJCAAAAA==.',
Re='Reeven:BAAANQAECgYIFAAAAQ==.Revokely:BAAANQAECgUICAAAAA==.',
Rh='Rhcpmage:BAAANQADCggICgABNQAECgkJKwADAEQmAA==.Rhetegast:BAAANQAECgcJEQAAAA==.',
Ri='Rike:BAAANQAECgQICQAAAA==.Ristretto:BAAANQADCgUJBQABNQAECgQIBQABAAAAAA==.',
Ro='Roland:BAAANQADCgUJBwAAAA==.Rolandin:BAAANQAECgQICQAAAA==.',
Ru='Rukraga:BAAANQAECgQJBAAAAA==.',
Ry='Rylagosa:BAAANQAECgUIBwAAAA==.Ryzesmidge:BAAANQAECgcJDAAAAA==.',
['Rê']='Rêdrum:BAAANQAECgIJAgABNQAECgcJFgAUAM8VAA==.',
Sa='Salandria:BAAANQAECgYIDwAAAA==.Sarionian:BAAANQAECgIJAgAAAA==.Sarjin:BAAANQADCgYIBgABNQAECgUJDAABAAAAAA==.Sarvinblue:BAABNQAECoEbAAMIAAkKYR69CgA4AwAIAAkKYR69CgA4AwASAAEKtwcG6QAsAAAAAA==.',
Sc='Scopolamine:BAAANQAECgEIAQAAAA==.',
Se='Sevrin:BAAANQAECgYIEQAAAA==.Seymonty:BAAANQAECgYJEAAAAA==.',
Sh='Shaeko:BAAANQADCgYJCgAAAA==.Shanir:BAAANQADCgIJAgAAAA==.Shazlulu:BAAANQAECgIJAgAAAA==.Shaznoir:BAAANQAECgUIDAAAAA==.Shilajit:BAAANQAECgIIBAAAAA==.Shokz:BAAANQADCgMIAwABNQAECgEJAQABAAAAAA==.',
Sk='Skip:BAAANQADCgcIBwAAAA==.Skøøma:BAAANQABCgIIBAAAAA==.',
Sl='Sloe:BAAANQAECgEJAQABNQAECgQIBQABAAAAAA==.',
Sm='Smokalot:BAAANQADCggICAAAAA==.Smokehunter:BAAANQADCgYIBgAAAA==.',
Sn='Snoop:BAAANQADCgQIBAAAAA==.',
So='Solstîce:BAAANQADCgQIBAABNQAECgcJFgAUAM8VAA==.',
Sp='Speedbeefbal:BAAANQADCgMJAwAAAA==.Speeddwrfbal:BAAANQADCgQIBAAAAA==.Speedmeat:BAAANQAECgUICAAAAA==.Speedmonkbal:BAAANQADCgUIAwAAAA==.Spidêrs:BAAANQABCgQICAAAAA==.Sporkulous:BAAANQAECgYIEwAAAA==.',
Sq='Squal:BAAANQAECgMIAwABNQAECgQIBAABAAAAAA==.Squiggle:BAAANQAECgUIBwAAAA==.',
St='Steevii:BAAANQADCgMJAwAAAA==.Stewie:BAAANQAECgEJAQAAAA==.Striker:BAAANQADCgUJCQABNQAECgQICQABAAAAAA==.',
Su='Sunshíne:BAAANQAECgIJAgAAAA==.',
Sy='Syver:BAAANQAECgUJCAAAAA==.',
['Sí']='Sírlancealot:BAAANQADCgMIBAAAAA==.',
Ta='Takeke:BAAANQAECgYIBwAAAA==.Takeroux:BAAANQADCgIIAgAAAA==.Talandroz:BAAANQAECgYIDgAAAA==.Tanagra:BAAANQADCgIIAgABNQAECgQICQABAAAAAA==.Tanner:BAABNQAECoEdAAIGAAkKphhELQB+AgAGAAkKphhELQB+AgAAAA==.',
Te='Tebo:BAAANQAECgEIAgAAAA==.Tedman:BAAANQAECgUIBwAAAA==.Temel:BAAANQAECgUICQAAAA==.Teostra:BAAANQAECgcIDgAAAA==.Testoecles:BAAANQADCgcICwABNQAECgEIAgABAAAAAA==.',
Th='Thadrack:BAAANQAECgYJCQAAAA==.Thalonstin:BAAANQADCgQICAAAAA==.Thaneold:BAAANQAECgQJCQABNQAECggJGwAVAM0hAA==.Thassarian:BAAANQAECgQIBAABNQAECgQJBAABAAAAAA==.Theodrid:BAACNQAFFIEHAAIWAAUKTxmnAQCvAQAWAAUKTxmnAQCvAQA1AAQKgSAAAhYACQoRIUoEADwDABYACQoRIUoEADwDAAAA.Thunderstomp:BAAANQADCgIIAgAAAA==.',
Ti='Tinkerspell:BAAANQADCgYICwAAAA==.Tinkíe:BAAANQAECgYIEQAAAA==.Tirzahdozier:BAAANQAECgEJAQABNQAECgIIBAABAAAAAA==.Tiwohnne:BAAANQADCgYICgAAAA==.',
Tl='Tla:BAAANQADCgQICAAAAA==.',
Tp='Tpaartos:BAAANQADCgIJAgABNQAECgQJBQABAAAAAA==.',
Tr='Treat:BAAANQAECgUICAAAAA==.Trippyshock:BAAANQADCgEIAQABNQAFFAcIEgAKALEfAA==.Tristitia:BAAANQABCgYIBwAAAA==.',
Tw='Twiggle:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.Twistedsquid:BAAANQABCgQIBAAAAA==.',
Ty='Tyamat:BAAANQAECgMJBgAAAA==.Tyche:BAAANQADCgUJBQAAAA==.Tyrinara:BAAANQADCggICAAAAA==.',
Ui='Uiewedaoez:BAAANQAECgYIEQAAAA==.',
Va='Vains:BAABNQAECoEcAAITAAgKNBpHOwBmAgATAAgKNBpHOwBmAgAAAA==.Valrith:BAAANQADCgcIGAAAAA==.',
Ve='Velody:BAAANQADCgQIAQAAAA==.Vendettuh:BAAANQADCgYIBgAAAA==.Veronica:BAAANQAECgQICAAAAA==.Verren:BAAANQAECgQJCAAAAA==.Vestus:BAAANQABCgcICQAAAA==.',
Vy='Vyrridyl:BAAANQAECgIIAwAAAA==.',
Wa='Watermark:BAAANQAECgUICQAAAA==.',
We='Weeblewobble:BAAANQAECgEIAgAAAA==.Weltamus:BAAANQADCgUJCQAAAA==.Weltazar:BAAANQAECgMIBAAAAA==.Weltzilla:BAAANQAECgQJBQAAAA==.Westside:BAAANQAECgMIBQAAAA==.',
Wh='Whoosh:BAAANQAECgYIEwAAAA==.',
Wi='Wickët:BAAANQAECgYIDwAAAA==.Wildtiger:BAAANQAECgUICAAAAA==.',
Wo='Wolfslied:BAAANQADCgQIBAABNQADCgQIBAABAAAAAA==.',
Wu='Wulfenhide:BAAANQAECgUICgAAAA==.',
Wy='Wyzsky:BAAANQADCgQIDgABNQAECgUICQABAAAAAA==.',
Xa='Xalreth:BAAANQAECgQICAAAAA==.Xaviana:BAAANQAECgUIBQAAAQ==.',
Ya='Yastypoo:BAAANQAECgcJDwAAAA==.',
Za='Zarieda:BAAANQAECgcJCwAAAA==.Zayrelia:BAABNQAECoEbAAMXAAcKIxb8NwCuAQAXAAYKtBb8NwCuAQAYAAYKihltHQCsAQAAAA==.',
Zu='Zud:BAAANQAECgUIDAAAAA==.',
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
