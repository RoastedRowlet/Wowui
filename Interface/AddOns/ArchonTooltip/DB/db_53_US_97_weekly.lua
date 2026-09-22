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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Demonology','Warrior-Arms','Shaman-Enhancement','DeathKnight-Blood','Paladin-Retribution','Druid-Balance','Hunter-Marksmanship','Evoker-Devastation','Rogue-Assassination','Warlock-Affliction','Monk-Mistweaver','Paladin-Protection','Monk-Windwalker','Druid-Feral','Druid-Restoration','Druid-Guardian','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Warrior-Fury','Warlock-Destruction','Paladin-Holy',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-09-22',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adwen:BAAANQADCgYIBgAAAA==.',
Ak='Akariala:BAAANQADCgYICwABNQAECgYJEgABAAAAAA==.Akittymeow:BAAANQAECgIIAgAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.Alidar:BAAANQAECgQJCQAAAA==.',
Am='Amberlie:BAAANQAECgcJCAAAAA==.Aminni:BAAANQAECgYJCwAAAA==.Amorgal:BAAANQADCgUICQAAAA==.Amorir:BAAANQAECgYJDwAAAA==.Amorydalias:BAAANQADCgcJCQAAAA==.',
An='Anastala:BAAANQAECgYJDAAAAA==.Andeddo:BAABNQAECoEaAAMCAAgK2xOQHQAQAgACAAgK2xOQHQAQAgADAAUK7AnSWwAGAQAAAA==.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJAgAAAA==.',
Ar='Archontas:BAAANQAECgYJDAAAAA==.Ariodecay:BAAANQAECgIJAgAAAA==.Ariodh:BAACNQAFFIEGAAIEAAQKXCISBACNAQAEAAQKXCISBACNAQA1AAQKgSUAAgQACQp3JnEAAPsDAAQACQp3JnEAAPsDAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arnak:BAAANQADCgMJAwAAAA==.Arpeggio:BAAANQADCgUIBQAAAA==.Artuarry:BAABNQAECoEhAAIFAAkKFhtXIQCjAgAFAAkKFhtXIQCjAgAAAA==.',
At='Athenà:BAAANQABCgQJBwAAAA==.',
Av='Avye:BAAANQAECgEJAQAAAA==.',
Ba='Bananus:BAAANQAECgQJBAAAAA==.Banthr:BAAANQAECgQIBgAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.',
Bi='Bigcow:BAAANQAECgYJEQAAAA==.Bigdeeps:BAABNQAECoEaAAIGAAgKqiMxFwAtAwAGAAgKqiMxFwAtAwAAAA==.',
Bl='Blackolives:BAAANQAECggJDQAAAA==.Blastcannon:BAAANQAECgYJEAAAAA==.Bluejuly:BAAANQABCgQJBwAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQADCgUIBQABNQAECgkJKQAHAIMeAA==.',
Br='Bravehearth:BAAANQADCgYIBgABNQADCgUIBQABAAAAAA==.',
Bu='Bubbadoo:BAAANQAECgYJDwAAAA==.Bulan:BAAANQAECgQJCQAAAA==.',
Ca='Candypants:BAAANQAECgYJDwAAAA==.Caoth:BAAANQAECgQJBAAAAA==.Cappilon:BAAANQAECgYJEAAAAA==.Carcus:BAAANQAECgcIDwAAAA==.Cayleedah:BAAANQAECgEIAQAAAA==.Cayssaris:BAAANQAECgEJAQAAAA==.',
Cc='Cc:BAAANQADCgQICAAAAA==.',
Ce='Ceeti:BAAANQAECgYJEQAAAA==.',
Ch='Chaewon:BAAANQAECgEIAQABNQAECgUJBwABAAAAAA==.Chaoticoreo:BAAANQADCgUIBQAAAA==.Chidaka:BAAANQAECgEJAgABNQAECgUIDQABAAAAAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUJBgAAAA==.',
Co='Corva:BAAANQAECgcIEwAAAA==.Cosairi:BAAANQAECgQIBQAAAA==.Cougztroll:BAAANQAECgYIDwAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAAANQAECggIDwAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECgYJEQABAAAAAA==.',
Cu='Cuttercupx:BAAANQAECgMIAwABNQAECgcIDAABAAAAAA==.',
Da='Dakadin:BAAANQAECgUIDQAAAA==.Daranne:BAAANQAECgcIDgAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECoEVAAIIAAYKXAr6WQANAQAIAAYKXAr6WQANAQAAAA==.Dashy:BAAANQAECgQIBAAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAAANQAECgYJEAAAAA==.Deafsmash:BAAANQAECgIJBAABNQAECgUIDAABAAAAAA==.Delamyr:BAAANQABCgIJAwAAAA==.Delina:BAAANQADCgYIBgAAAA==.Denaric:BAAANQABCgQIBwABNQAECgEJAQABAAAAAA==.Destroyevsky:BAAANQADCgcIFwAAAA==.Detonate:BAAANQADCgUICQAAAA==.',
Di='Digem:BAAANQABCgQJBAABNQADCgcIEwABAAAAAA==.',
Do='Dolphinz:BAABNQAECoEWAAIJAAkKMiIcEABUAwAJAAkKMiIcEABUAwAAAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgYIDAABAAAAAA==.Dragonwarior:BAAANQAECgUIDQAAAA==.Drykkr:BAAANQAECgUIDQAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECgcJCAABAAAAAA==.Element:BAAANQADCgQIBAAAAA==.Elpollo:BAAANQADCggIEQAAAA==.Elvar:BAAANQADCgUJCAAAAA==.',
Ep='Epitome:BAAANQAECgYJDwAAAA==.',
Er='Erid:BAAANQAECgcJCgAAAA==.',
Eu='Eunha:BAAANQAECgEIAQABNQAECgUJBwABAAAAAA==.',
Ev='Evergrey:BAAANQAECgQIBAAAAA==.Evermoons:BAAANQAECgUIDQAAAA==.',
Fa='Falaria:BAAANQADCgcJCQAAAA==.Falasdaer:BAAANQAECgQIBgAAAA==.Falstaff:BAAANQADCgcJDgAAAA==.Fatalis:BAAANQADCggJGgAAAA==.Fatterblunt:BAABNQAECoEhAAIKAAkKZBgZIABuAgAKAAkKZBgZIABuAgAAAA==.',
Fe='Feldar:BAAANQAECgQJCQAAAA==.Feronite:BAABNQAECoEpAAIHAAkKgx4PAwBLAwAHAAkKgx4PAwBLAwAAAA==.',
Fi='Fizzleclaw:BAAANQAECgEJAQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAECgEJAQABAAAAAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAAANQAECgIIBwAAAA==.',
Fr='Fredwin:BAAANQAECgQIBAAAAA==.Free:BAAANQADCgcIDQABNQADCgcJEgABAAAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgAAAA==.Furvert:BAAANQAECgcIDAAAAA==.',
Ga='Ganthex:BAAANQADCgUJBQAAAA==.Gapper:BAABNQAECoEdAAILAAkK2RxZCwDuAgALAAkK2RxZCwDuAgAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAAANQAECgYICgAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAAANQAECgYIBgAAAA==.',
Go='Gojira:BAAANQAECgEJAQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAAANQAECgUJDwAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgYIDgAMAIIIAA==.Grollosh:BAAANQABCgQIBgAAAA==.Grymwarr:BAAANQAECgEJAQAAAA==.',
Ha='Haerin:BAAANQAECgEIAQABNQAECgUJBwABAAAAAA==.Hairydresden:BAAANQABCgIJAgAAAA==.Harnel:BAAANQAECgQJBgAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgEJAQAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Hordedefect:BAAANQAECgEIAQABNQAECgcIDAABAAAAAA==.Hoyer:BAAANQAECgIIAgAAAA==.',
Hu='Humbledrink:BAAANQADCgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQADCgIIAgABNQADCgcJEgABAAAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQADCgIIAgABNQAECgkJKQAHAIMeAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgEJAQAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Jy='Jyade:BAAANQAECgEJAQAAAA==.',
Ka='Kaiserice:BAAANQADCgcIBwAAAA==.Kaliel:BAAANQADCgUIDAAAAA==.Kamarra:BAAANQAECgEIAQAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgUJBQAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAECgkJKgAFAFIiAA==.',
Ke='Kernelpanic:BAABNQAECoEWAAMDAAgK2B+UFQDBAgADAAgKzh6UFQDBAgACAAEKrhGeaQA9AAAAAA==.Keyoshi:BAAANQAECgYIBgAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQADCgYJBgAAAA==.Kirkle:BAAANQAECgYJEQAAAA==.',
Ko='Kovy:BAAANQADCgYICgAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAECgkJKgAFAFIiAA==.Krukar:BAAANQAECgEIAQAAAA==.',
Kw='Kwovie:BAAANQAECgUIDgAAAA==.',
Ky='Kynaria:BAAANQADCgYIDgAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAAANQAECgQJCQAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgQIBAAAAA==.Lavasaurus:BAAANQADCgcIEwABNQAECgQIBAABAAAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgMIBQAAAA==.Lesclaypool:BAAANQADCgcJCwAAAA==.Lewd:BAAANQAECgYJCgAAAA==.',
Li='Lifebloomz:BAAANQAECgUJCgAAAA==.Lilfluffcc:BAAANQAECgcJDwAAAA==.',
Lo='Lockward:BAAANQAECgcIEgAAAA==.Lorblor:BAAANQAECgUICQAAAA==.Lowang:BAAANQAECgIIAgAAAA==.Lowmeinn:BAAANQAECgUJCQAAAA==.',
Lt='Ltningbolt:BAAANQADCgUICgAAAA==.',
Lu='Lucidlux:BAAANQAECgcJDAAAAA==.Lunafox:BAAANQAECggJDgAAAA==.Lunamae:BAAANQAECgUJDAAAAA==.Luvvyaa:BAAANQAECgQJBAABNQAECgcIEwABAAAAAA==.Luvvyyaa:BAAANQAECgcIEwAAAA==.Luvyya:BAAANQADCggICAABNQAECgcIEwABAAAAAA==.',
Ly='Lythomancer:BAAANQAECgQIBwAAAA==.',
Ma='Maddeena:BAAANQAECgEJAQAAAA==.Magicmandunz:BAAANQADCggIDgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAABNQAECoEqAAIFAAkKUiKxCABNAwAFAAkKUiKxCABNAwAAAA==.',
Mc='Mcmercie:BAAANQAECgYICQAAAA==.',
Me='Mechacooter:BAABNQAECoEbAAINAAgKMRofEACPAgANAAgKMRofEACPAgAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAAANQAECgYJDAAAAA==.Melchiorr:BAABNQAECoEeAAIOAAgKfxgmAwBtAgAOAAgKfxgmAwBtAgAAAA==.Melynne:BAAANQAECgYJDgAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgQIBwABAAAAAA==.Minsoo:BAABNQAECoEZAAIPAAgKWBvOCgB5AgAPAAgKWBvOCgB5AgAAAA==.',
Ml='Mlrgl:BAAANQAECgYIBAAAAA==.Mlrglo:BAAANQAECgUJBgABNQAECgYIBAABAAAAAA==.',
Mo='Mormegil:BAAANQADCgcIFwAAAA==.Moshimoshi:BAAANQAFFAEIAQAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAAANQAECgEJAQAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQADCgUICAABNQAECggIGwANADEaAA==.',
Ne='Nessará:BAAANQAECgUJDgAAAA==.',
Ni='Nightgodjuju:BAAANQAECgUICQAAAA==.Nikna:BAAANQAECgUIBgABNQAECgcIEQABAAAAAA==.',
Nu='Nuraga:BAAANQAECgUIBwAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAAANQAECgUIDgAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAAANQAECgYIDAAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQAAAA==.Pattilicious:BAAANQAECgYJDgAAAA==.',
Ph='Phonedin:BAAANQAECgUIDgAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECoEYAAIQAAcK6gmKIgA6AQAQAAcK6gmKIgA6AQAAAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECgcIDQABAAAAAA==.',
Qu='Quilue:BAAANQAECgMJBAAAAA==.',
Ra='Rannmagnison:BAAANQAECgQJCQAAAA==.Raquoon:BAAANQAECgEJAQAAAA==.Razzalghoul:BAAANQAECgUJCgAAAA==.',
Re='Reze:BAABNQAECoEbAAIRAAkK8CEsBgA3AwARAAkK8CEsBgA3AwABNQAFFAcJGAAEADclAA==.',
Rh='Rhaeynera:BAAANQAECgMJBAAAAA==.',
Ri='Riezen:BAAANQAECgQIEAAAAA==.Rinorik:BAAANQAECgYJDAAAAA==.',
Ro='Rockhhard:BAAANQAECgIIAgAAAA==.Roeken:BAAANQAECgYIDAAAAA==.Rollingman:BAAANQADCgcIEQAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAAANQAECgUIDgAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAAANQAECgUICQAAAA==.',
Sa='Samsó:BAAANQAECgQJCQAAAA==.Sapharina:BAAANQAECgYJEgAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECoEXAAQSAAgKRRnSCAATAgASAAYKVxzSCAATAgATAAYKuhdDHAC5AQAUAAIK/xEmKQBmAAAAAA==.Schreckstoff:BAAANQAECgYJDwAAAA==.',
Se='Searfang:BAABNQAECoEZAAIVAAgKuBjrKwBhAgAVAAgKuBjrKwBhAgAAAA==.Septik:BAAANQADCggJDAAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAgAAAA==.Shashashmoo:BAABNQAECoEXAAIKAAcKAxDqOQChAQAKAAcKAxDqOQChAQAAAA==.Shlum:BAAANQADCgcIEwAAAA==.',
Si='Silaslunark:BAAANQAECgIIAgAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skëëts:BAAANQADCgQJAwAAAA==.',
Sl='Sleatsz:BAAANQADCggICAAAAA==.Sleez:BAAANQAECgQJBAAAAA==.Slimesmile:BAAANQAECgIJAgAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBAABAAAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIDwABAAAAAA==.',
Sn='Snowscayia:BAABNQAECoEpAAMTAAkKRx6rBABEAwATAAkKRx6rBABEAwAKAAgKaQu6NgC3AQAAAA==.Snypes:BAAANQAECggIEgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAAANQAECgYJDAAAAA==.',
Sq='Squadie:BAAANQAECgQICAAAAA==.Squanchs:BAABNQAECoEeAAIWAAkKFSb4AADQAwAWAAkKFSb4AADQAwABNQAECgYJBwABAAAAAA==.Squanchy:BAAANQAECgYJBwAAAA==.',
Sr='Srry:BAAANQAECgYJBwAAAA==.',
St='Story:BAAANQADCgUJBwAAAA==.Styrcius:BAAANQAECgYJDgAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQADCgEIAQABNQADCgEIAQABAAAAAA==.Suniah:BAAANQAECgIIAgAAAA==.Sustmage:BAAANQAECgIIAQABNQAFFAUJBwAGAAsfAA==.',
['Sü']='Sünny:BAAANQADCgcIBwAAAA==.Süß:BAAANQADCgIIAgABNQAECggIFwASAEUZAA==.',
Ta='Tabius:BAAANQAECgUIDQAAAA==.Talkingtaco:BAAANQAECgIIBAAAAA==.',
Te='Teddumby:BAAANQADCgcICAABNQAECgcIDAABAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAAANQAECgEJAQAAAA==.',
Th='Thelorìn:BAAANQAECgQJBAAAAA==.Thiccdiq:BAAANQAECgYJDAAAAA==.Thirstycow:BAAANQAECgYJBgAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thosen:BAAANQABCgIIAgAAAA==.',
Ti='Tinytina:BAAANQAECgQJBAAAAA==.',
To='Tore:BAABNQAECoEjAAIXAAkKWiOHBQCPAwAXAAkKWiOHBQCPAwAAAA==.',
Tr='Trinadel:BAABNQAECoEZAAIKAAgKfRdXJABJAgAKAAgKfRdXJABJAgAAAA==.Tråitors:BAAANQAECgQJCAAAAA==.',
Ts='Tsarevich:BAAANQAECgEJAQAAAA==.',
Tw='Twileaf:BAAANQAECgIIAwAAAA==.',
Ul='Ully:BAAANQAECgIJAwAAAA==.',
Un='Unholyaltec:BAABNQAECoEWAAIDAAgKlgobNgDLAQADAAgKlgobNgDLAQAAAA==.Unug:BAAANQADCggICAABNQAECgYJEAABAAAAAA==.',
Ut='Uthmansur:BAAANQAECgEIAQAAAA==.',
Va='Varkbyte:BAAANQAECgEIAQAAAA==.Varrik:BAABNQAECoEbAAMGAAgKHR5XLwCtAgAGAAgK3h1XLwCtAgAYAAEK0R1KHwBEAAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAAANQAECgYJEgAAAA==.Voyageurs:BAABNQAECoEaAAISAAgKkx11BADJAgASAAgKkx11BADJAgAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECgcJCAABAAAAAA==.Vyrka:BAAANQAECgEIAQAAAA==.',
['Vÿ']='Vÿc:BAAANQADCgEIAQAAAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQADCgEIAQAAAA==.',
Wh='Whatmurda:BAAANQAECgEJAQABNQAECgQJCAABAAAAAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDAABAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Wish:BAAANQAECgYJEwAAAA==.',
Wo='Wonyoung:BAAANQAECgUJBwAAAA==.',
Wr='Wraithwok:BAAANQAECgMIAwAAAA==.',
Wu='Wuthrad:BAAANQAECgQIBAAAAA==.',
Wy='Wyze:BAAANQADCgYJBgAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQADCgQIBQAAAA==.',
Xe='Xelienn:BAAANQAECgUJEgAAAA==.Xelojr:BAAANQADCgUJEQAAAA==.',
Xi='Xia:BAAANQAECgYJEAAAAA==.Xilhaunt:BAABNQAECoEYAAQZAAgKdhdxGACPAQAFAAcK0xK7TADsAQAZAAYK2BRxGACPAQAOAAQKShQGDQAHAQAAAA==.',
Xo='Xoilbiis:BAAANQADCgYICwAAAA==.Xoilkick:BAAANQAECgQIBAAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAAANQADCgYICQAAAA==.',
['Xê']='Xêna:BAAANQADCggIFAAAAA==.',
['Xì']='Xì:BAAANQADCgQIBAAAAA==.',
Yb='Yb:BAAANQAECgQJBQABNQAECgkJHQALANkcAA==.',
Ye='Yellowsnøw:BAAANQAECgQIBAAAAA==.',
Yu='Yumeshade:BAAANQAECgQIBAAAAA==.',
Za='Zaak:BAAANQAECgYIDwAAAA==.Zamari:BAAANQADCggJJAAAAA==.Zanzabar:BAAANQAECgUIBQAAAA==.',
Ze='Zelfie:BAAANQAECgEJAQAAAA==.Zeliek:BAABNQAECoEfAAIaAAkKTBhFGADMAgAaAAkKTBhFGADMAgABNQAECgkJHwAaAEwYAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.',
Zo='Zoerina:BAAANQAECgQIBwAAAA==.Zoobilong:BAAANQAECgcIEAAAAA==.',
Zx='Zxak:BAAANQADCggIEAABNQAECgYIDwABAAAAAA==.',
['Zë']='Zën:BAAANQAECgYIEgAAAA==.',
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
