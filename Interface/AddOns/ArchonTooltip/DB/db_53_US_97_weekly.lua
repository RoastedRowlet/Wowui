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

local lookup = {'Priest-Holy','DeathKnight-Unholy','DeathKnight-Frost','DemonHunter-Havoc','Warlock-Demonology','Warrior-Arms','Mage-Frost','Mage-Arcane','Shaman-Enhancement','Unknown-Unknown','Druid-Balance','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Warlock-Destruction','Paladin-Retribution','DeathKnight-Blood','Hunter-Marksmanship','Monk-Windwalker','Druid-Guardian','Rogue-Assassination','Warlock-Affliction','Evoker-Preservation','Paladin-Protection','Hunter-BeastMastery','Druid-Feral','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-Survival','Paladin-Holy',}
local provider = {region='US',realm='Fizzcrank',name='US',type='weekly',zone=53,date='2026-09-29',data={Ac='Acky:BAAANQAECgIIAgAAAA==.',
Ad='Adoboy:BAAANQADCgYIBgAAAA==.Adwen:BAAANQADCgYIBgAAAA==.',
Ak='Akariala:BAAANQADCgYICwABNQAECggIGQABAL4NAA==.Akittymeow:BAAANQAECgIIAgAAAA==.',
Al='Aldredevon:BAAANQABCgIIAgAAAA==.',
Am='Amberlie:BAAANQAECggICAAAAA==.Aminni:BAAANQAECgcIEgAAAA==.Amorgal:BAAANQADCgUICQAAAA==.Amorir:BAAANQAECgYIDwAAAA==.Amorydalias:BAAANQAECgMIAwAAAA==.',
An='Anastala:BAAANQAECgYIEgAAAA==.Andeddo:BAABNQAECoEiAAMCAAkKlxhcHwCGAgACAAkKSxdcHwCGAgADAAgK2xN5KQDtAQAAAA==.Annelya:BAAANQADCgcIBwAAAA==.Annesta:BAAANQAECgIJAgAAAA==.',
Ar='Archontas:BAAANQAECgYIEAAAAA==.Ariodecay:BAAANQAECgIIAgAAAA==.Ariodh:BAACNQAFFIEJAAIEAAQKYSM5BgCKAQAEAAQKYSM5BgCKAQA1AAQKgScAAgQACQp8JuYAAOwDAAQACQp8JuYAAOwDAAAA.Arkaline:BAAANQADCgMIAwAAAA==.Arkham:BAAANQAECgMIAwAAAA==.Arnak:BAAANQADCgMJAwAAAA==.Arpeggio:BAAANQADCgUICgAAAA==.Artuarry:BAACNQAFFIEHAAIFAAQKIQxzDgAoAQAFAAQKIQxzDgAoAQA1AAQKgSQAAgUACQo4G/sxAIYCAAUACQo4G/sxAIYCAAAA.',
At='Athenà:BAAANQABCgQJBwAAAA==.',
Av='Avye:BAAANQAECgQIBQAAAA==.',
Ba='Bananus:BAAANQAECgUIBQAAAA==.Banthr:BAAANQAECgUICwAAAA==.',
Be='Bearglie:BAAANQADCgIIAgAAAA==.Beepers:BAAANQADCgEIAQAAAA==.',
Bi='Bigcow:BAAANQAECgYJEQAAAA==.Bigdeeps:BAABNQAECoEhAAIGAAgKAiRjHAAmAwAGAAgKAiRjHAAmAwAAAA==.',
Bl='Blackolives:BAAANQAECggIEwAAAA==.Blastcannon:BAABNQAECoEcAAMHAAgKFwQrFQAYAQAHAAcKYQQrFQAYAQAIAAEKDAKgrAEQAAAAAA==.Bluejuly:BAAANQABCgQJBwAAAA==.',
Bo='Bomboclat:BAAANQAECgQIDgAAAA==.Bowwie:BAAANQADCgUIBQABNQAECgkJKQAJAIMeAA==.',
Br='Bravehearth:BAAANQADCgYIBgABNQADCgUIBQAKAAAAAA==.',
Bu='Bubbadoo:BAABNQAECoEWAAILAAcKBxFTPwCvAQALAAcKBxFTPwCvAQAAAA==.Bulan:BAAANQAECgYIDwAAAA==.',
Ca='Candypants:BAABNQAECoEWAAIMAAcKoBhpEgADAgAMAAcKoBhpEgADAgAAAA==.Caoth:BAAANQAECgQIBAAAAA==.Cappilon:BAABNQAECoEZAAIHAAcKFyOnAwDHAgAHAAcKFyOnAwDHAgAAAA==.Carcus:BAAANQAECgcIDwAAAA==.Cayleedah:BAAANQAECgMIBAAAAA==.Cayssaris:BAAANQAECgQIBQAAAA==.',
Cc='Cc:BAAANQADCgQICwAAAA==.',
Ce='Ceeti:BAABNQAECoEZAAMNAAgKdBx1BQBFAgANAAgKrRl1BQBFAgAOAAYKFRrYEwDOAQAAAA==.',
Ch='Chaewon:BAAANQAECgEIAQABNQAECgcICAAKAAAAAA==.Chaoticoreo:BAAANQADCgUIBQAAAA==.Chidaka:BAAANQAECgEJAgABNQAECgUIEgAKAAAAAA==.Chilia:BAAANQABCgIIAgAAAA==.Chips:BAAANQADCgUIBgAAAA==.',
Co='Corva:BAABNQAECoEXAAMFAAkKJxTmXgDsAQAFAAcKXhfmXgDsAQAPAAUKTAxTMQDrAAAAAA==.Cosairi:BAAANQAECgYICwAAAA==.Cougztroll:BAAANQAECgYIDwAAAA==.',
Cr='Crazybarbie:BAAANQADCgIIAgAAAA==.Crnknineties:BAAANQAECggIEQAAAA==.Crossie:BAAANQADCgEIAQAAAA==.',
Ct='Ctd:BAAANQADCgQIBQABNQAECggIGQANAHQcAA==.',
Cu='Cuttercupx:BAAANQAECgQIBQABNQAECgcIDQAKAAAAAA==.',
Da='Dakadin:BAAANQAECgUIEgAAAA==.Daranne:BAABNQAECoEcAAIQAAkKQRqFOgCgAgAQAAkKQRqFOgCgAgAAAA==.Darknite:BAAANQADCgEIAQAAAA==.Darkwrand:BAABNQAECoEaAAIRAAYKggv9ZgAMAQARAAYKggv9ZgAMAQAAAA==.Dashy:BAAANQAECgQIBAAAAA==.Dashyy:BAABNQAECoEeAAIBAAkKShq1KgCAAgABAAkKShq1KgCAAgAAAA==.Dawnstone:BAAANQAECgQICgAAAA==.',
De='Dead:BAAANQADCgcIDQAAAA==.Deaduglie:BAAANQAECgYJEAAAAA==.Deafsmash:BAAANQAECgIJBAABNQAECgcIEwAKAAAAAA==.Delamyr:BAAANQABCgIJAwABNQADCgYIBgAKAAAAAA==.Delina:BAAANQADCgYIBgAAAA==.Denaric:BAAANQABCgQIBwABNQAECgMIBAAKAAAAAA==.Destroyevsky:BAAANQAECgIIAgAAAA==.Detonate:BAAANQADCgUICQAAAA==.',
Di='Digem:BAAANQABCgQJBAABNQADCgcIEwAKAAAAAA==.',
Do='Dolphinz:BAABNQAECoEZAAIQAAkKuSKQGAA8AwAQAAkKuSKQGAA8AwAAAA==.',
Dr='Dragonkyle:BAAANQADCgYIEAABNQAECgkJGAAMAOUbAA==.Dragonwarior:BAAANQAECgUIDQAAAA==.Drykkr:BAAANQAECgUIEgAAAA==.',
El='Elcrys:BAAANQADCggJCgABNQAECggICAAKAAAAAA==.Element:BAAANQADCgQIBAAAAA==.Elpollo:BAAANQADCggIEgAAAA==.Elvar:BAAANQADCgYICgAAAA==.',
Em='Emolo:BAAANQADCgMIAwABNQAECggIFgAQAIsNAA==.',
Ep='Epitome:BAABNQAECoEVAAIHAAYKOxrqCgDDAQAHAAYKOxrqCgDDAQAAAA==.',
Er='Erid:BAAANQAECgcIEQAAAA==.',
Et='Etude:BAAANQAECgEIAQAAAA==.',
Eu='Eunha:BAAANQAECgEIAgABNQAECgcICAAKAAAAAA==.',
Ev='Evallyn:BAAANQADCgYIBgABNQAECgYIGgARAIILAA==.Evergrey:BAAANQAECgQIBAAAAA==.Evermoons:BAAANQAECgUIEgAAAA==.',
Fa='Falaria:BAAANQADCgcJCQAAAA==.Falasdaer:BAAANQAECgQIBgAAAA==.Falstaff:BAAANQADCgcJDgAAAA==.Fatalis:BAAANQADCggIHgAAAA==.Fatterblunt:BAACNQAFFIEGAAILAAMK5QtTEQDcAAALAAMK5QtTEQDcAAA1AAQKgSQAAgsACQriGoAkAHMCAAsACQriGoAkAHMCAAAA.',
Fe='Feldar:BAAANQAECgYIDwAAAA==.Feronite:BAABNQAECoEpAAIJAAkKgx74BAAjAwAJAAkKgx74BAAjAwAAAA==.',
Fi='Fizzleclaw:BAAANQAECgQIBQAAAA==.Fizzleded:BAAANQADCgIIAgABNQAECgQIBQAKAAAAAA==.Fizzlelock:BAAANQADCgYIBgAAAA==.',
Fo='Fordi:BAAANQADCggIHQAAAA==.Fourdy:BAAANQAECgQICwAAAA==.',
Fr='Fredwin:BAAANQAECgcICwAAAA==.Free:BAAANQADCgcIDQABNQAECgQIBAAKAAAAAA==.Froost:BAAANQADCgYIBgAAAA==.',
Fu='Funkflex:BAAANQADCgcJEgABNQAECgQIBAAKAAAAAA==.Furvert:BAAANQAECgcIDQAAAA==.',
Ga='Ganthex:BAAANQADCgUJBQAAAA==.Gapper:BAABNQAECoEmAAISAAkKWB/vCAAoAwASAAkKWB/vCAAoAwAAAA==.Gargodath:BAAANQABCgQIBwAAAA==.',
Gi='Gimbó:BAAANQADCgUIBQAAAA==.',
Gl='Glaistig:BAAANQADCggICAAAAA==.Glestaar:BAAANQAECgYIEAAAAA==.Glooks:BAAANQADCgUIBQAAAA==.',
Gn='Gnommaash:BAAANQAECgcIDAAAAA==.',
Go='Gojira:BAAANQAECgQIBQAAAA==.Golgaria:BAAANQABCgIIAgAAAA==.Gothri:BAABNQAECoEXAAMMAAcKXRupEAAnAgAMAAcKXRupEAAnAgATAAEKCA8YUwA0AAAAAA==.',
Gr='Grimli:BAAANQADCgQIBAABNQAECgcIEQAOADYKAA==.Grollosh:BAAANQABCgYICAAAAA==.Grymwarr:BAAANQAECgQIBQAAAA==.',
Ha='Haerin:BAAANQAECgUICAABNQAECgcICAAKAAAAAA==.Hairydresden:BAAANQABCgIIAgAAAA==.Harnel:BAAANQAECgUICwAAAA==.Hattorihanzo:BAAANQADCgUIBwAAAA==.',
He='Healmart:BAAANQAECgEIAQAAAA==.Hellborne:BAAANQABCgIIAgAAAA==.',
Hi='Hiperion:BAAANQADCgUIBQAAAA==.',
Ho='Holykovie:BAAANQADCgUIBQAAAA==.Hordedefect:BAAANQAECgEIAQABNQAECgcIDQAKAAAAAA==.Hoyer:BAAANQAECgIIAgAAAA==.',
Hu='Humbledrink:BAAANQADCgUIBQAAAA==.',
In='Ingraver:BAAANQABCgEIAQAAAA==.Insomnia:BAAANQAECgQIBAAAAA==.',
Ir='Irishkiss:BAAANQADCggICwAAAA==.',
Ja='Jakub:BAAANQADCgIIAgABNQAECgkJKQAJAIMeAA==.Jamous:BAAANQADCgYIDAAAAA==.',
Je='Jesit:BAAANQAECgEJAQAAAA==.',
Jo='Joeyporterjr:BAAANQADCgEIAQAAAA==.',
Jy='Jyade:BAAANQAECgEIAgAAAA==.',
Ka='Kaiserice:BAAANQAECgYIBgAAAA==.Kaliel:BAAANQADCgUIEAAAAA==.Kamarra:BAAANQAECgEIAQAAAA==.Kamencider:BAAANQADCgQICgAAAA==.Karjo:BAAANQAECgUJBQAAAA==.Karson:BAAANQADCgUIBQAAAA==.Kayati:BAAANQADCgcIBwABNQAFFAUICgAFAEgRAA==.',
Ke='Kernelpanic:BAACNQAFFIEHAAMCAAQK/BnoCwC8AAACAAMKyRHoCwC8AAADAAIKZBmhCwCqAAA1AAQKgRkAAwIACApnIDAiAHECAAIACArOHjAiAHECAAMAAQolFi1+AD8AAAAA.Keyoshi:BAAANQAECgYIBgAAAA==.',
Ki='Kilgarnish:BAAANQADCgYICQAAAA==.Kilrinstinct:BAAANQADCgYIDgAAAA==.Kirkle:BAABNQAECoEdAAIPAAgKBRfCCABfAgAPAAgKBRfCCABfAgAAAA==.',
Ko='Kovis:BAAANQABCgUIBgAAAA==.Kovy:BAAANQADCgYICgAAAA==.Kovya:BAAANQADCgQJBAAAAA==.',
Kr='Kristang:BAAANQADCggICAABNQAFFAUICgAFAEgRAA==.Krukar:BAAANQAECgEIAQAAAA==.',
Ku='Kulrath:BAAANQAECggIAgAAAA==.',
Kw='Kwovie:BAABNQAECoEXAAIUAAcKShlbDgABAgAUAAcKShlbDgABAgAAAA==.',
Ky='Kynaria:BAAANQADCgYIDgAAAA==.Kyrotten:BAAANQADCgMIAwAAAA==.',
La='Lamörak:BAAANQAECgYIDwAAAA==.Landrick:BAAANQADCgQIBAAAAA==.Lastshot:BAAANQADCgYIBgAAAA==.Latentpasta:BAAANQADCgUIBQAAAA==.Lavamancer:BAAANQAECgQIBAABNQAECgQIBAAKAAAAAA==.Lavasaurus:BAAANQAECgQIBAAAAA==.',
Le='Leafstorm:BAAANQADCgcIEwAAAA==.Leokenoso:BAAANQAECgMIBQAAAA==.Lesclaypool:BAAANQADCgcICwAAAA==.Lewd:BAAANQAECgYIDQAAAA==.',
Li='Lifebloomz:BAAANQAECgYIEAAAAA==.Lilfluffcc:BAAANQAECgcIEgAAAA==.',
Lo='Lockward:BAAANQAECgcIEgAAAA==.Lorblor:BAAANQAECgYIDwAAAA==.Lowang:BAAANQAECgIIAgAAAA==.Lowmeinn:BAAANQAECgUJCQAAAA==.',
Lt='Ltningbolt:BAAANQADCgUICgAAAA==.',
Lu='Lucidlux:BAAANQAECggIEwAAAA==.Lunafox:BAAANQAECggIDwAAAA==.Lunamae:BAAANQAECgUIEQAAAA==.Luvvyaa:BAAANQAECgQICAABNQAECgkJHgABAEoaAA==.Luvyya:BAAANQADCggICAABNQAECgkJHgABAEoaAA==.',
Ly='Lythomancer:BAAANQAECgYICwAAAA==.',
Ma='Maddeena:BAAANQAECgQIBQAAAA==.Magicmandunz:BAAANQADCggIDgAAAA==.Malidian:BAAANQADCgUIBQAAAA==.Maxohlx:BAACNQAFFIEKAAIFAAUKSBGlBwCQAQAFAAUKSBGlBwCQAQA1AAQKgS4AAgUACQp5IowLAEsDAAUACQp5IowLAEsDAAAA.',
Mc='Mcmercie:BAAANQAECgcIDgAAAA==.',
Me='Mechacooter:BAABNQAECoEfAAIVAAkK+RnQDwDBAgAVAAkK+RnQDwDBAgAAAA==.Megg:BAAANQADCgEIAQAAAA==.Meksheepy:BAAANQAECgcIEwAAAA==.Melchiorr:BAABNQAECoEkAAIWAAgKlRn4AwBnAgAWAAgKlRn4AwBnAgAAAA==.Melynne:BAAANQAECgYJDgAAAA==.',
Mi='Miku:BAEANQADCgYICwABNQAECgYICgAKAAAAAA==.Minji:BAAANQAECgYIBgABNQAECgcICAAKAAAAAA==.Minsoo:BAABNQAECoEZAAIMAAgKWBvPDQBhAgAMAAgKWBvPDQBhAgAAAA==.',
Ml='Mlrgl:BAAANQAECggICwAAAA==.Mlrglo:BAAANQAECgUJBgABNQAECggICwAKAAAAAA==.',
Mo='Mormegil:BAAANQAECgQIBAAAAA==.Moshimoshi:BAAANQAFFAIIAwAAAA==.Motosake:BAAANQADCgUIBQAAAA==.',
Mu='Muriana:BAAANQADCgEIAQAAAA==.',
My='Mythaera:BAAANQAECgQIBQAAAA==.',
Na='Naberius:BAAANQAECgMIBAAAAA==.Nagashunters:BAAANQADCgMIAwAAAA==.Najuma:BAAANQADCgIIAgAAAA==.',
Nb='Nbg:BAAANQADCgUICAABNQAECgkJHwAVAPkZAA==.',
Ne='Nessará:BAAANQAECgUIEgAAAA==.',
Ni='Nightgodjuju:BAAANQAECgUICQAAAA==.Nikna:BAAANQAECgUICwABNQAFFAEIAQAKAAAAAA==.',
Nu='Nuraga:BAAANQAECgUIDAAAAA==.',
Ob='Obviate:BAAANQAECgEIAQAAAA==.',
On='Onarius:BAAANQADCgIIAgAAAA==.Onazix:BAAANQAECgUIEwAAAA==.',
Pa='Pandaemonia:BAAANQAECgYIBgAAAA==.Pandakyle:BAABNQAECoEYAAIMAAkK5RsLCADiAgAMAAkK5RsLCADiAgAAAA==.Patchmen:BAAANQADCgcIBwAAAA==.Patootie:BAAANQADCgEIAQABNQAECgYIBgAKAAAAAA==.Pattilicious:BAAANQAECgcIEgAAAA==.',
Ph='Phonedin:BAABNQAECoEZAAMOAAcKiRaJEgDoAQAOAAcKiRaJEgDoAQAXAAQKhxHTLADuAAAAAA==.',
Po='Postwillow:BAAANQADCgcIBwAAAA==.Powerochrist:BAABNQAECoEeAAIYAAgKQBBFHACwAQAYAAgKQBBFHACwAQAAAA==.',
Py='Pyrug:BAAANQADCgUIBQABNQAECgYJEAAKAAAAAA==.',
['Pá']='Pád:BAAANQAECgQIBgABNQAECggIFwAZAPIMAA==.',
Qu='Quilue:BAAANQAECgYICgAAAA==.',
Ra='Rannmagnison:BAAANQAECgUIDgAAAA==.Raquoon:BAAANQAECgQIBQAAAA==.Razzalghoul:BAAANQAECgYIEAAAAA==.',
Re='Reuli:BAAANQAECgIIAgAAAA==.Reze:BAABNQAECoEbAAITAAkK8CHwCQAJAwATAAkK8CHwCQAJAwABNQAFFAcIHgAEAKslAA==.',
Rh='Rhaeynera:BAAANQAECgUICQAAAA==.',
Ri='Riezen:BAABNQAECoEaAAICAAYKFBkySACQAQACAAYKFBkySACQAQAAAA==.Rinorik:BAAANQAECgcIEwAAAA==.',
Ro='Rockbiter:BAAANQADCgUIBQAAAA==.Rockhhard:BAAANQAECgIIAgAAAA==.Roeken:BAAANQAECgYIEgAAAA==.Rollingman:BAAANQAECgQIBAAAAA==.Roony:BAAANQADCgUICAAAAA==.',
Ru='Rubens:BAAANQAECgUIEwAAAA==.Ruzala:BAAANQADCggICQAAAA==.Ruzz:BAAANQADCgcIFAAAAA==.',
Ry='Rybear:BAAANQADCgcICwAAAA==.Ryutiz:BAAANQAECgYIDwAAAA==.',
Sa='Samsó:BAAANQAECgYIDwAAAA==.Sapharina:BAABNQAECoEZAAIBAAgKvg37WQC0AQABAAgKvg37WQC0AQAAAA==.Sartinar:BAAANQADCgYIBgAAAA==.',
Sc='Scharf:BAABNQAECoEZAAQaAAkK+hq1CABbAgAaAAcKixy1CABbAgAbAAYKyhjtIgCuAQAUAAIK/xHJNABjAAAAAA==.Schreckstoff:BAABNQAECoEVAAIcAAYKVxJvbACGAQAcAAYKVxJvbACGAQAAAA==.',
Se='Searfang:BAABNQAECoEfAAIcAAkK0BfDLQCGAgAcAAkK0BfDLQCGAgAAAA==.Septik:BAAANQADCggJDAAAAA==.',
Sh='Shadowmidget:BAAANQAECgIIAgAAAA==.Shashashmoo:BAABNQAECoEXAAILAAcKAxDyQwCTAQALAAcKAxDyQwCTAQAAAA==.Shlum:BAAANQADCgcIEwAAAA==.',
Si='Silaslunark:BAAANQAECgQIBwAAAA==.',
Sk='Skooty:BAAANQADCgQIBAAAAA==.Skëëts:BAAANQADCgUIBQAAAA==.',
Sl='Slampoof:BAAANQABCggIDAAAAA==.Sleatsz:BAAANQADCggICAAAAA==.Sleez:BAAANQAECgQJBAAAAA==.Slime:BAAANQAECgcIBwAAAA==.Slimesmile:BAAANQAECgIIAwAAAA==.',
Sm='Smallgregory:BAAANQADCgQIBAABNQAECgQJBAAKAAAAAA==.Smashmaster:BAAANQADCgEIAQAAAA==.Smøk:BAAANQADCgQIBAABNQAECgcIDwAKAAAAAA==.',
Sn='Snowscayia:BAABNQAECoE4AAMbAAkKkh8rBABnAwAbAAkKkh8rBABnAwALAAgKrgxaPgC0AQAAAA==.Snypes:BAABNQAECoEWAAILAAkKJhyJGQDNAgALAAkKJhyJGQDNAgAAAA==.',
So='Socks:BAAANQADCggIEAAAAA==.Solmina:BAAANQAECgcIEwAAAA==.',
Sq='Squadie:BAAANQAECgYIDgAAAA==.Squanchs:BAABNQAECoEhAAIdAAkKFSaIAQDAAwAdAAkKFSaIAQDAAwABNQAECgYIBwAKAAAAAA==.Squanchy:BAAANQAECgYIBwAAAA==.',
Sr='Srry:BAAANQAECgYIBwAAAA==.',
St='Story:BAAANQADCgUICwAAAA==.Styrcius:BAABNQAECoEUAAIYAAYKRh2LGADbAQAYAAYKRh2LGADbAQAAAA==.Stôrmfang:BAAANQADCggIDgAAAA==.',
Su='Sundance:BAAANQAECgYIBgAAAA==.Suniah:BAAANQAECgUIBwAAAA==.Sustmage:BAAANQAECgIIAQABNQAFFAUICwAGAAsfAA==.',
Sy='Sydris:BAAANQAECggIBwAAAA==.',
['Sü']='Sünny:BAAANQADCgcIBwAAAA==.Süß:BAAANQADCgIIAgABNQAECgkJGQAaAPoaAA==.',
Ta='Tabius:BAAANQAECgUIEgAAAA==.Talkingtaco:BAAANQAECgIIBAAAAA==.',
Te='Teddumby:BAAANQADCgcICAABNQAECgcIDQAKAAAAAA==.Telilina:BAAANQADCggJCAAAAA==.Temok:BAAANQAECgQIBQAAAA==.',
Th='Thelorìn:BAAANQAECgYICgAAAA==.Thiccdiq:BAAANQAECgcIEwAAAA==.Thiccgirl:BAAANQABCgMIBAAAAA==.Thirstycow:BAAANQAECgYIBwAAAA==.Thorkell:BAAANQADCgcIDAAAAA==.Thosen:BAAANQABCgIIAgAAAA==.',
Ti='Tinytina:BAAANQAECgQJBAAAAA==.',
To='Tore:BAABNQAECoEwAAIZAAkKAyRNBACtAwAZAAkKAyRNBACtAwAAAA==.Torqued:BAAANQADCggICAAAAA==.',
Tr='Trinadel:BAABNQAECoEdAAILAAkKjRaQIQCLAgALAAkKjRaQIQCLAgAAAA==.Tråitors:BAAANQAECgUIDQAAAA==.',
Ts='Tsarevich:BAAANQAECgQIBQAAAA==.',
Tw='Twileaf:BAAANQAECgUICAAAAA==.',
Ul='Ully:BAAANQAECgIIAwAAAA==.',
Un='Unholyaltec:BAABNQAECoEeAAICAAgKhBDkPQDDAQACAAgKhBDkPQDDAQAAAA==.Unug:BAAANQADCggIDgABNQAECgYJEAAKAAAAAA==.',
Ut='Uthmansur:BAAANQAECgIIAgAAAA==.',
Va='Varkbyte:BAAANQAECgQIBQAAAA==.Varrik:BAABNQAECoEjAAMGAAgKXR4mPQCbAgAGAAgKJB4mPQCbAgAeAAEK0R0IJQBAAAAAAA==.Vaulari:BAAANQADCggICAAAAA==.',
Ve='Velamor:BAAANQADCgEIAQAAAA==.Ventus:BAAANQADCgUIBQAAAA==.',
Vi='Vivrae:BAAANQADCgYIBwAAAA==.',
Vo='Voleandre:BAAANQAECgYJEgAAAA==.Voyageurs:BAABNQAECoEaAAIaAAgKkx1kBgCvAgAaAAgKkx1kBgCvAgAAAA==.',
Vy='Vynn:BAAANQADCgQIBAABNQAECggICAAKAAAAAA==.Vyrka:BAAANQAECgQIBQAAAA==.',
['Vÿ']='Vÿc:BAAANQADCgEIAQAAAA==.',
Wa='Waterdweller:BAAANQADCgUICAAAAA==.Wayhigh:BAAANQADCgIIAgAAAA==.',
We='Wesleypipes:BAAANQADCgEIAQAAAA==.Wetheals:BAAANQAECgEIAQAAAA==.',
Wh='Whatmurda:BAAANQAECgQIBQABNQAECgUIDQAKAAAAAA==.Wheredergo:BAAANQADCggIDwABNQAECgcIDQAKAAAAAA==.Whosurpally:BAAANQADCgUIBwAAAA==.',
Wi='Wiindslashh:BAAANQADCgEIAQAAAA==.Windslash:BAAANQADCgYIBgAAAA==.Wish:BAAANQAECgYJEwAAAA==.',
Wo='Wonhee:BAAANQAECgUIBQABNQAECgcICAAKAAAAAA==.Wonyoung:BAAANQAECgcICAAAAA==.',
Wr='Wraithwok:BAAANQAECgMIAwAAAA==.',
Wu='Wuthrad:BAAANQAECgQICAAAAA==.',
Wy='Wyze:BAAANQADCgYJBgAAAA==.',
Xa='Xaced:BAAANQAECgcIBwAAAA==.Xandboni:BAAANQADCgQIBQAAAA==.',
Xe='Xelienn:BAABNQAECoEZAAMDAAcK5xzZIAA0AgADAAcK5xzZIAA0AgACAAIKMANIpQBGAAAAAA==.Xellor:BAAANQADCgYIBgAAAA==.Xelojr:BAAANQADCgYIFgAAAA==.',
Xi='Xia:BAAANQAECgYJEAAAAA==.Xilhaunt:BAABNQAECoEhAAQPAAkKWxywBADIAgAPAAkKkBiwBADIAgAFAAgKWRT7RwA4AgAWAAQKShQgEAD+AAAAAA==.',
Xo='Xoilbiis:BAAANQADCgYIEQAAAA==.Xoilkick:BAAANQAECgYICgAAAA==.Xoilpal:BAAANQADCgMIAwAAAA==.Xoilwings:BAAANQADCgYIDgAAAA==.',
['Xê']='Xêna:BAAANQADCggIFAAAAA==.',
['Xì']='Xì:BAAANQADCgQIBAAAAA==.',
Yb='Yb:BAAANQAECgYICwABNQAECgkJJgASAFgfAA==.',
Ye='Yellowsnøw:BAAANQAECgQIBAAAAA==.',
Yu='Yumeshade:BAAANQAECgQIBAAAAA==.',
Za='Zaak:BAABNQAECoEbAAIfAAgKQSQHAQBhAwAfAAgKQSQHAQBhAwAAAA==.Zamari:BAAANQAECgQIBAAAAA==.Zanzabar:BAAANQAECgYICQAAAA==.',
Ze='Zelfie:BAAANQAECgEJAQAAAA==.Zeliek:BAABNQAECoEhAAIgAAkKJxobFwD1AgAgAAkKJxobFwD1AgABNQAECgkJIQAgACcaAA==.Zerodarkness:BAAANQADCgQIBAAAAA==.Zerooné:BAAANQADCgYIDAAAAA==.',
Zo='Zoerina:BAAANQAECgYIDQAAAA==.Zoobilong:BAABNQAECoEWAAIQAAgKiw3dgQC/AQAQAAgKiw3dgQC/AQAAAA==.',
Zx='Zxak:BAAANQADCggIEAABNQAECggIGwAfAEEkAA==.',
['Zë']='Zën:BAABNQAECoEbAAMIAAgKrAhkywCeAQAIAAgK9wdkywCeAQAHAAEKCQ9EPAAwAAAAAA==.',
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
