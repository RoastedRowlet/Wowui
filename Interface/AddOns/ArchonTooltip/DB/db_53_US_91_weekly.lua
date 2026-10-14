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

local lookup = {'Druid-Balance','Shaman-Elemental','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DemonHunter-Devourer','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Rogue-Assassination','Druid-Restoration','Warlock-Destruction','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Warlock-Affliction','Priest-Discipline','Hunter-Survival','Warrior-Protection','DeathKnight-Blood',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-10-13',data={Al='Alodiar:BAAANQADCgUICQAAAA==.',
Am='Amadellaves:BAAANQADCgQIBAAAAA==.',
An='Andersen:BAAANQADCgEIAQAAAA==.Andryu:BAABNQAECn8jAAIBAAkKfxDKNgAyAgABAAkKfxDKNgAyAgAAAA==.Annde:BAABNQAECn8pAAICAAkKTBjVOACQAgACAAkKTBjVOACQAgAAAA==.Anyana:BAAANQADCgQIBAABNQAECgQJBAADAAAAAA==.',
Ar='Ardre:BAAANQADCgUIBQABNQADCgUICQADAAAAAA==.Artemus:BAACNQAFFH8KAAMEAAUK1gMwBgAsAQAEAAUK1gMwBgAsAQAFAAMKIgSeDgCcAAA1AAQKfzEAAwQACQqrHscJAOoCAAQACQqrHscJAOoCAAUABwqODukzAHEBAAE1AAQKAQgBAAMAAAAA.Arïel:BAAANQAECgQIDAAAAA==.',
Be='Beeftoteeth:BAAANQAECgUIBwAAAA==.Ber:BAAANQAECgQICwABNQAFFAQIBQAGAE4HAA==.Bexxy:BAAANQAECgEIAgAAAA==.',
Bi='Bibicrits:BAAANQABCggIDgABNQAECgkJLQAHAB8eAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgYIEQAAAA==.',
Br='Broadfang:BAACNQAFFH8cAAMIAAcKQRXEBwDLAQAIAAYKrhTEBwDLAQAJAAMK2RiIGADyAAA1AAQKfzIAAwgACQpgIVUUALsCAAgACQrRH1UUALsCAAkAAQofJA86AWcAAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICAAAAA==.Bullorly:BAACNQAFFH8KAAIKAAUK3B3HBADdAQAKAAUK3B3HBADdAQA1AAQKfysAAgoACQrwJWAFAKEDAAoACQrwJWAFAKEDAAAA.',
Ca='Catirus:BAAANQADCgYIBwAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECgkJLwAEAJUZAA==.Chunt:BAAANQADCgcIBwAAAA==.',
Cl='Cleo:BAAANQAECgUIEwAAAA==.Clipe:BAAANQAFFAEIAQAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQADCgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgIIAwAAAA==.',
Cr='Crispicrits:BAAANQAECgUICAABNQAECgkJIQALAIQZAA==.',
Cy='Cynîc:BAAANQAECgMIBgAAAA==.',
Da='Dalaran:BAABNQAECn8wAAIHAAkK9wuzKQDxAQAHAAkK9wuzKQDxAQAAAA==.Darenas:BAACNQAFFH8LAAIMAAUKFRO6CQBfAQAMAAUKFRO6CQBfAQA1AAQKfzIAAgwACQozHi4OAAoDAAwACQozHi4OAAoDAAAA.Darkwing:BAAANQABCgIIAQABNQAECgUIDAADAAAAAA==.',
De='Deathbooze:BAABNQAECn8nAAIKAAkKsCHRGQDwAgAKAAkKsCHRGQDwAgAAAA==.Deathmikee:BAABNQAECn8lAAIKAAkKSyFGEAA0AwAKAAkKSyFGEAA0AwAAAA==.Delilah:BAAANQAECgYIDQAAAA==.Delita:BAAANQAECgMIAwAAAA==.Demonea:BAAANQADCgYIBgAAAA==.Derek:BAAANQAECgUIBwAAAA==.',
Dr='Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECn8sAAMNAAkKvByMAwAbAwANAAkKvByMAwAbAwAOAAMK6wssFQGrAAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECggIBgAAAA==.',
El='Elderdorje:BAABNQAECn8vAAMEAAkKlRnMDgCRAgAEAAkKlRnMDgCRAgAFAAcKUAVcRgDlAAAAAA==.Elixe:BAAANQADCggICAAAAA==.Elmersglue:BAAANQADCgEIAQAAAA==.Elondre:BAABNQAECn8wAAIPAAkKph9lEwAuAwAPAAkKph9lEwAuAwAAAA==.',
Ev='Evangeliné:BAAANQADCggICAABNQAECggIJAALAB4QAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECn8tAAIHAAkKHx4fCgA2AwAHAAkKHx4fCgA2AwAAAA==.',
Fi='Firecracker:BAAANQAECgYICwAAAA==.',
Fo='Fortwooh:BAAANQADCgcIEwAAAA==.',
Fr='Freshlight:BAAANQAECgIIAwABNQAFFAIIBQAEAEUTAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQADCgQIBQABNQAFFAQIBQAGAE4HAA==.Galatea:BAABNQAECn89AAIQAAkKYCFJLgANAwAQAAkKYCFJLgANAwAAAA==.Galifen:BAABNQAECn8xAAIBAAkKwyW0AQDjAwABAAkKwyW0AQDjAwAAAA==.Gank:BAABNQAECn8kAAIRAAkKyyGIBACLAwARAAkKyyGIBACLAwAAAA==.Gardener:BAAANQABCgIIBAAAAA==.',
Gh='Ghreen:BAAANQAECgYICAAAAA==.',
Gi='Gilgahmesh:BAAANQAECgUIDAAAAA==.',
Gn='Gnomegrown:BAAANQAECgUIDgAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAQAAAA==.',
Gy='Gyrux:BAAANQAECgEIAQAAAA==.',
Ha='Halyer:BAAANQADCggIFwAAAA==.Hamalainen:BAAANQAECgYIEAABNQAFFAIIBQAEAEUTAA==.Harrydresden:BAAANQABCgIIBAAAAA==.Havøc:BAAANQAECgMIAwAAAA==.',
He='Helioboops:BAAANQADCggIEQAAAA==.',
Ho='Hobbz:BAACNQAFFH8LAAIQAAUKXRmrDQBrAQAQAAUKXRmrDQBrAQA1AAQKfyoAAhAACQoVJCUWAGsDABAACQoVJCUWAGsDAAAA.',
Il='Illandros:BAAANQAECgUIEwAAAA==.',
In='Inspire:BAACNQAFFH8NAAISAAUKEhVkBwCBAQASAAUKEhVkBwCBAQA1AAQKfykAAhIACQpOIjMJAC8DABIACQpOIjMJAC8DAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgQIBQAAAA==.',
Ja='Jaína:BAAANQAECgIIAgABNQAECgUIDgADAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAFFAIIBQAEAEUTAA==.',
Je='Jelina:BAAANQAECgIIAgAAAA==.',
Ji='Jiren:BAACNQAFFH8FAAIEAAIKRRN9CQCOAAAEAAIKRRN9CQCOAAA1AAQKfy4AAgQACQr6HZwJAO4CAAQACQr6HZwJAO4CAAAA.',
Jo='Johnson:BAAANQAECgcIEwAAAA==.Joran:BAAANQAECgUIEAAAAA==.',
Kr='Kro:BAAANQADCgEIAQAAAA==.',
Le='Leanea:BAAANQAECgIIAgAAAA==.',
Li='Liera:BAAANQAECgYIEAAAAA==.Lightsac:BAAANQADCgYIBgAAAA==.Limmywinks:BAAANQADCgQIBAAAAA==.',
Ll='Lloydlei:BAAANQAECgcIDwAAAA==.',
Lu='Luminå:BAABNQAECn8hAAITAAkK3xlqBADlAgATAAkK3xlqBADlAgAAAA==.',
Ma='Maibisan:BAABNQAECn9IAAMUAAkKJyYtAQDsAwAUAAkKJyYtAQDsAwAHAAcKiyLhHQBfAgAAAA==.Malificent:BAAANQAECgMIAwAAAA==.',
Me='Metaevoker:BAABNQAECn8xAAIVAAkKnxoACwC3AgAVAAkKnxoACwC3AgAAAA==.',
Mo='Monawah:BAABNQAECn8aAAIJAAgKFAv2igDxAQAJAAgKFAv2igDxAQAAAA==.Mookong:BAAANQADCgYIBwAAAA==.Moonsliver:BAAANQAECgEIAwAAAA==.Moorf:BAAANQAECgcIDwAAAA==.Morff:BAABNQAECn8WAAIVAAcKEwu/HwBWAQAVAAcKEwu/HwBWAQAAAA==.Motleychew:BAAANQADCggIEgAAAA==.',
My='Mystwolf:BAAANQAECgUJBwAAAA==.',
Ne='Ned:BAAANQADCgMIAwABNQAECgUICQADAAAAAA==.',
Ni='Nightember:BAAANQADCgIIAgABNQAECgkJLwAEAJUZAA==.Nightski:BAAANQAECgYIDQAAAA==.Nizzari:BAAANQAECgEIBAABNQAFFAQIBQAGAE4HAA==.',
No='Nobuseri:BAAANQADCgUIBQAAAA==.Nothalyer:BAABNQAECn8qAAIWAAkK2gdJIwCpAQAWAAkK2gdJIwCpAQAAAA==.',
['Nå']='Nåtrii:BAAANQADCgYIBgABNQAECgcIEwADAAAAAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgUICQAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQAECgEIAgADAAAAAA==.Orwasitme:BAAANQAECgEIAgAAAA==.Orwasitmii:BAAANQADCgMJAwABNQAECgEIAgADAAAAAA==.',
Pa='Paladinii:BAAANQADCgQICgAAAA==.',
Ph='Philonk:BAABNQAECn8cAAIFAAkKgRBIJgDtAQAFAAkKgRBIJgDtAQAAAA==.',
Pj='Pjxyo:BAAANQAECgYIEAAAAA==.',
Po='Polytots:BAACNQAFFH8QAAMPAAUKHQ5xDgBiAQAPAAUKHQ5xDgBiAQACAAIKcwlVJgCQAAA1AAQKfzkAAw8ACQpZJe8BAMgDAA8ACQpZJe8BAMgDAAIAAQpoIfARAWIAAAAA.',
Ps='Psycototem:BAAANQAECgMIBwAAAA==.',
Ra='Razius:BAAANQAECggIDgAAAA==.',
Re='Rebexha:BAAANQAECgUIDgAAAA==.Recoiless:BAAANQADCgYIBgAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAAANQAECgEIAwABNQAFFAIIBQAEAEUTAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ry='Ryzenther:BAAANQAECgIJAwAAAA==.',
['Rà']='Ràgnar:BAAANQAECgMIAgAAAA==.Ràgñar:BAAANQADCgYIEQAAAA==.',
Sc='Scarpa:BAAANQAECgEIAQABNQAECgkJLQABALIUAA==.Scathclipe:BAABNQAECn8lAAMRAAkKeBWMLQArAgARAAkK4xGMLQArAgAXAAgKvxTvCAADAgAAAA==.',
Se='Seancodi:BAAANQAECgEIAQABNQAFFAYIFQAHAPIdAA==.Senomage:BAABNQAECn8eAAMYAAkKFSJzNQAeAwAYAAkKFSJzNQAeAwAZAAMK/R2EHwDqAAAAAA==.Serphentos:BAAANQABCgIIAgAAAA==.',
Sh='Shasato:BAABNQAECn8fAAIaAAkKAx/4BQAyAwAaAAkKAx/4BQAyAwAAAA==.Shazrast:BAAANQADCgQIBAAAAA==.Shockss:BAAANQAECgUICgAAAA==.',
Si='Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECn8iAAILAAkK1gtUaADhAQALAAkK1gtUaADhAQAAAA==.',
Sk='Skyepic:BAACNQAFFH8hAAMbAAcKUh18AgCBAgAbAAcKUh18AgCBAgAcAAEKTgVWEQA+AAA1AAQKfyYAAhsACQp+JgoBAOMDABsACQp+JgoBAOMDAAAA.Skylight:BAAANQAECggIDAAAAA==.',
Sn='Sneakfu:BAABNQAECn8kAAMRAAgKuRViMgAPAgARAAgKKhBiMgAPAgAdAAcKaBY2HQDmAQAAAA==.Snugwalnut:BAACNQAFFH8QAAIPAAYK6RCoCADDAQAPAAYK6RCoCADDAQA1AAQKfykAAg8ACQr0HuIzAI4CAA8ACQr0HuIzAI4CAAAA.',
So='Soejoedi:BAABNQAECn8tAAIBAAkKshQyJwCYAgABAAkKshQyJwCYAgAAAA==.Sorrowin:BAAANQABCgIIAgAAAA==.',
Sp='Spicyburrito:BAAANQAECgIIAgAAAA==.',
St='Stitchzpls:BAAANQAECgIIBAAAAA==.',
Ta='Taintedrush:BAACNQAFFH8FAAIeAAMKAgf3AgDMAAAeAAMKAgf3AgDMAAA1AAQKfykAAh4ACQqPGBcDANQCAB4ACQqPGBcDANQCAAAA.Tarhostamir:BAAANQAECgMIAwAAAA==.Taurup:BAAANQADCgYIEAABNQAFFAQIBQAGAE4HAA==.Tazz:BAABNQAECn8ZAAMJAAcK4QLg5wAsAQAJAAcK4QLg5wAsAQAIAAEKAAAVngAaAAAAAA==.',
Te='Teenjus:BAAANQADCgcICAAAAA==.',
Th='Thaluus:BAAANQADCgUIBwAAAA==.Thanossnap:BAAANQABCgQIBgABNQAECgkJLwAEAJUZAA==.Thaysinga:BAABNQAECn8cAAIKAAcKyxMbXwCPAQAKAAcKyxMbXwCPAQAAAA==.Thelandlord:BAAANQAECgIIAgAAAA==.Thunderblast:BAAANQAECgUICgAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQADCgcIFAAAAA==.',
Tr='Trollor:BAAANQADCggIHQAAAA==.',
Ut='Utzon:BAAANQADCgQJBAABNQAECgkJLQABALIUAA==.',
Va='Vaedan:BAAANQADCgcIDAAAAA==.Valkyrrie:BAAANQADCgUIBQABNQADCggIFwADAAAAAA==.Vander:BAAANQAECgUIDwAAAA==.Vannder:BAAANQAECgEIAgABNQAECgUIDwADAAAAAA==.Vayper:BAABNQAECn8yAAQMAAkKECKhBgBtAwAMAAkKECKhBgBtAwALAAIKyQkJ4AB/AAAfAAEK8gS+LgAmAAAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgkJMgAMABAiAA==.',
Ve='Veins:BAAANQADCgEIAQAAAA==.',
['Vë']='Vënöm:BAAANQAECgEIAQABNQAECgkJIQATAN8ZAA==.',
Wa='Waggo:BAABNQAECn8hAAICAAcKrBBfgQCdAQACAAcKrBBfgQCdAQAAAA==.Waken:BAAANQAECgQICAAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgUIBQABNQADCgUIBgADAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAQAAAA==.',
Wi='Wildfire:BAACNQAFFH8JAAIgAAYKABxEAAA9AgAgAAYKABxEAAA9AgA1AAQKfygAAiAACQp5Jk8AANUDACAACQp5Jk8AANUDAAAA.',
Wo='Wolfhammer:BAABNQAECn8nAAIhAAkKwRjmCQCmAgAhAAkKwRjmCQCmAgAAAA==.',
Wr='Wreckadin:BAABNQAECn8YAAIQAAkKmB2lQADQAgAQAAkKmB2lQADQAgAAAA==.',
Ya='Yaztraz:BAABNQAECn8mAAMPAAkKWx4/PgBkAgAPAAgKuh0/PgBkAgACAAYKPgnyrAA1AQAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQABNQAFFAcIIAAiABEiAA==.',
Za='Zarturion:BAAANQAECgEIAQAAAA==.',
Zo='Zod:BAACNQAFFH8FAAMGAAQKTgejBwDNAAAGAAMK1AmjBwDNAAAVAAEKQQIYEQAyAAA1AAQKfzAAAwYACQq3F7gEALACAAYACQq3F7gEALACABUABAoQC48rAMUAAAAA.',
['Às']='Àsh:BAAANQAECggIEgAAAA==.',
['Év']='Évangeline:BAAANQAECgQIBgABNQAECggIJAALAB4QAA==.',
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
