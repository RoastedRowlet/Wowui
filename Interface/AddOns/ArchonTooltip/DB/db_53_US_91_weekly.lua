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

local lookup = {'Druid-Balance','Shaman-Elemental','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Warrior-Fury','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Rogue-Assassination','Hunter-Survival','Druid-Restoration','Warrior-Protection','Warlock-Destruction','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Druid-Guardian','Paladin-Holy','Paladin-Protection','Rogue-Subtlety','Warlock-Affliction','Priest-Discipline',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=53,date='2026-10-20',data={Al='Alodiar:BAAANQADCgUICQAAAA==.',
Am='Amadellaves:BAAANQADCgQIBwAAAA==.',
An='Andersen:BAAANQADCgEIAQAAAA==.Andryu:BAABNQAECn8qAAIBAAoKgxDQGQAUAQABAAoKgxDQGQAUAQAAAA==.Annde:BAABNQAECn8tAAICAAoKIxiSOQCQAgACAAoKIxiSOQCQAgAAAA==.Anyana:BAAANQADCgQIBAABNQAECgQJBAADAAAAAA==.',
Ar='Ardre:BAAANQADCgUIBQABNQADCgUICQADAAAAAA==.Artemus:BAACNQAFFH8LAAMEAAYKMAlSBgAsAQAEAAUK1gNSBgAsAQAFAAQKaAPhDgCcAAA1AAQKfzMAAwQACgq1HeoJAOoCAAQACgq1HeoJAOoCAAUABwqODoQ0AHEBAAE1AAQKAggDAAMAAAAA.Arïel:BAAANQAECgUIDAAAAA==.',
Be='Beeftoteeth:BAAANQAECgYIBwAAAA==.Ber:BAAANQAECgYIEQABNQAFFAQICQAGAAkIAA==.Bexxy:BAAANQAECgQIBQAAAA==.',
Bi='Bibicrits:BAAANQABCggIDgABNQAECgoKMwAHAE8eAA==.',
Bl='Blueseno:BAAANQADCgYIBgAAAA==.',
Bo='Bouras:BAAANQAECgYIEQAAAA==.',
Br='Broadfang:BAACNQAFFH8gAAMIAAcKDhpjAwAvAQAJAAYKrhTzBwDLAQAIAAYK+RpjAwAvAQA1AAQKfzYAAwkACgqTIZ4UALoCAAkACQpeIZ4UALoCAAgAAgqLI82fAG4AAAAA.',
Bu='Bubbleoseven:BAAANQAECgYICAAAAA==.Bullorly:BAACNQAFFH8KAAIKAAUK3B3YBADeAQAKAAUK3B3YBADeAQA1AAQKfywAAgoACgqTJHUFAKEDAAoACgqTJHUFAKEDAAAA.',
Ca='Catirus:BAAANQADCgYICAAAAA==.',
Ch='Chareddh:BAAANQADCgMIAwABNQAECgoKNAAEAIAbAA==.Cheehoo:BAAANQADCgQIBAAAAA==.Chunt:BAAANQADCgcIBwAAAA==.',
Cl='Cleo:BAABNQAECn8WAAMLAAcKWAEkfQCCAAALAAcKWAEkfQCCAAAHAAUK7QAiYwBeAAAAAA==.Clipe:BAAANQAFFAEIAQAAAA==.Clipee:BAAANQADCgEIAQAAAA==.Clipeskeg:BAAANQADCgEIAQAAAA==.Clipex:BAAANQADCgMIAwAAAA==.Clipey:BAAANQADCggIDgAAAA==.',
Co='Coldsnap:BAAANQADCgQIBgAAAA==.Connor:BAAANQADCgYICgAAAA==.Control:BAAANQAECgMIAwAAAA==.',
Cr='Crimsonpaw:BAAANQADCggIDwAAAA==.Crispicrits:BAAANQAECgYICgABNQAECgoKIgAMAKYYAA==.',
Cy='Cynîc:BAAANQAECgMIBgAAAA==.',
Da='Dalaran:BAABNQAECn81AAIHAAoKYQszKgDxAQAHAAoKYQszKgDxAQAAAA==.Darenas:BAACNQAFFH8MAAINAAYKAxD5CQBeAQANAAYKAxD5CQBeAQA1AAQKfzMAAg0ACgpCHF4OAAkDAA0ACgpCHF4OAAkDAAAA.Darkwing:BAAANQABCgIIAQABNQAECgYIDQADAAAAAA==.',
De='Deathbooze:BAABNQAECn8nAAIKAAkKsCEYGgDwAgAKAAkKsCEYGgDwAgAAAA==.Deathmikee:BAABNQAECn8qAAIKAAoKnB5iEAA0AwAKAAoKnB5iEAA0AwAAAA==.Delilah:BAAANQAECgYIDQAAAA==.Delita:BAAANQAECgMIAwAAAA==.Demonea:BAAANQADCgYIBgAAAA==.Derek:BAAANQAECgUIBwAAAA==.',
Dr='Drakos:BAAANQADCggIEAAAAA==.',
Du='Durton:BAABNQAECn8wAAMOAAoKER2RAwAcAwAOAAoKER2RAwAcAwAPAAMK6wuQGAGrAAAAAA==.',
Ec='Echø:BAAANQADCgUIBQAAAA==.',
Ed='Edrency:BAAANQADCgYIBgAAAA==.',
Ef='Eferis:BAAANQAECggIBwAAAA==.',
El='Elderdorje:BAABNQAECn80AAMEAAoKgBtBBgCIAQAEAAoKgBtBBgCIAQAFAAcKUAVDRwDlAAAAAA==.Elmersglue:BAAANQADCgEIAQAAAA==.Elondre:BAABNQAECn85AAIQAAoKrSC/AQBVAwAQAAoKrSC/AQBVAwAAAA==.',
Ev='Evangeliné:BAAANQADCggIDAABNQAECggIKwAMAAYRAA==.',
Ex='Execfive:BAAANQADCgIIAQAAAA==.',
Fe='Femboi:BAABNQAECn8zAAIHAAoKTx5YCgA1AwAHAAoKTx5YCgA1AwAAAA==.',
Fi='Firecracker:BAAANQAECgYICwAAAA==.',
Fo='Fortwooh:BAAANQADCgcIEwAAAA==.',
Fr='Freshlight:BAAANQAECgQICAABNQAFFAIIBgAEAEUTAA==.',
Fu='Fuurak:BAAANQAFFAEIAQAAAA==.',
Ga='Gado:BAAANQADCgQIBQABNQAFFAQICQAGAAkIAA==.Galatea:BAABNQAECn9HAAIRAAoKhx9ALwAMAwARAAoKhx9ALwAMAwAAAA==.Galifen:BAABNQAECn83AAIBAAoKHybBAQDjAwABAAoKHybBAQDjAwAAAA==.Gank:BAABNQAECn8pAAISAAoKoSKuBACLAwASAAoKoSKuBACLAwAAAA==.Gardener:BAAANQABCgIIBAAAAA==.',
Gh='Ghreen:BAAANQAECgYICAAAAA==.',
Gi='Gilgahmesh:BAAANQAECgYIDQAAAA==.',
Gn='Gnomegrown:BAABNQAECn8UAAIBAAYK8QwEYwBCAQABAAYK8QwEYwBCAQAAAA==.',
Go='Gothika:BAAANQADCgIIAgAAAA==.Goy:BAAANQAECgcIAQAAAA==.',
Gr='Grainbelt:BAAANQAECggICAAAAA==.',
Gy='Gyrux:BAAANQAECgEIAQAAAA==.',
Ha='Halyer:BAAANQADCggIFwAAAA==.Hamalainen:BAABNQAECn8bAAMTAAkKChADCQC0AQATAAYKyBMDCQC0AQAIAAkKYQoHegC5AAABNQAFFAIIBgAEAEUTAA==.Harrydresden:BAAANQABCgIIBAAAAA==.Havøc:BAAANQAECgMIAwAAAA==.',
He='Helioboops:BAAANQADCggIEQAAAA==.',
Ho='Hobbz:BAACNQAFFH8MAAIRAAYK+hQDDgBrAQARAAYK+hQDDgBrAQA1AAQKfzEAAhEACgqKI5IIAFgCABEACgqKI5IIAFgCAAAA.',
Il='Illandros:BAABNQAECn8dAAINAAYKCw88PABIAQANAAYKCw88PABIAQAAAA==.',
In='Inspire:BAACNQAFFH8NAAIUAAUKEhWhBwCBAQAUAAUKEhWhBwCBAQA1AAQKfyoAAhQACgqOImcJAC8DABQACgqOImcJAC8DAAAA.',
Is='Isinia:BAAANQADCgEIAQAAAA==.Isira:BAAANQAECgcICQAAAA==.',
Ja='Jaína:BAAANQAECgIIAgABNQAECgYIDgADAAAAAA==.',
Jc='Jcvd:BAAANQADCgYICwABNQAFFAIIBgAEAEUTAA==.',
Je='Jelina:BAAANQAECgMIAwAAAA==.',
Ji='Jiren:BAACNQAFFH8GAAIEAAIKRROtCQCOAAAEAAIKRROtCQCOAAA1AAQKfzQAAwQACgoaH8AJAO4CAAQACgoaH8AJAO4CAAUAAgqMBFM8AB8AAAAA.',
Jo='Johnson:BAABNQAECn8XAAIVAAgK2BWIEQAOAgAVAAgK2BWIEQAOAgAAAA==.Joran:BAABNQAECn8XAAIRAAYKqQnA+QArAQARAAYKqQnA+QArAQAAAA==.',
Kr='Kro:BAAANQADCgEIAQAAAA==.',
La='Laststop:BAAANQADCgYIBQAAAA==.',
Le='Leanea:BAAANQAECgIIAgAAAA==.',
Li='Liera:BAABNQAECn8UAAIKAAgKjxBwXwCRAQAKAAgKjxBwXwCRAQAAAA==.Lightsac:BAAANQADCgYIBgAAAA==.Limmywinks:BAAANQADCgQIBwAAAA==.',
Ll='Lloydlei:BAAANQAECgcIDwAAAA==.',
Lu='Luminå:BAABNQAECn8hAAIWAAkK3xltBADkAgAWAAkK3xltBADkAgAAAA==.',
Ma='Maibisan:BAABNQAECn9RAAMLAAoKqiU4AQDsAwALAAoKqiU4AQDsAwAHAAgKBSJCHgBfAgAAAA==.Malificent:BAAANQAECgMIAwAAAA==.',
Me='Metaevoker:BAABNQAECn83AAIXAAoK0xohCwC2AgAXAAoK0xohCwC2AgAAAA==.',
Mo='Monawah:BAABNQAECn8dAAIIAAgKFAv5jADwAQAIAAgKFAv5jADwAQAAAA==.Mookong:BAAANQADCgYIBwAAAA==.Moonsliver:BAAANQAECgEIAwAAAA==.Moorf:BAABNQAECn8VAAMQAAgKFwrRRADbAAAQAAcKfAvRRADbAAACAAEKAACPZAEPAAAAAA==.Morff:BAABNQAECn8WAAIXAAcKEwv/HwBWAQAXAAcKEwv/HwBWAQAAAA==.Motleychew:BAAANQADCggIEgAAAA==.',
My='Mystwolf:BAAANQAECgUJBwAAAA==.',
Ne='Ned:BAAANQADCgMIAwABNQAECgUIDgADAAAAAA==.',
Ni='Nightember:BAAANQADCgIIAgABNQAECgoKNAAEAIAbAA==.Nightski:BAABNQAECn8UAAIUAAcKWxctBwDSAQAUAAcKWxctBwDSAQAAAA==.Nizzari:BAAANQAECgMIBgABNQAFFAQICQAGAAkIAA==.',
No='Nobuseri:BAAANQAECgQIBAAAAA==.Nothalyer:BAABNQAECn8wAAIYAAoKPAeaIwCoAQAYAAoKPAeaIwCoAQAAAA==.',
['Nå']='Nåtrii:BAAANQADCggICAABNQAECggIGgAYAJ4IAA==.',
Ob='Obliviora:BAAANQADCgYIBgAAAA==.',
Og='Ogdi:BAAANQAECgUIDgAAAA==.',
Ol='Olaria:BAAANQADCgMIAwAAAA==.',
Or='Orwasitgarp:BAAANQADCgYIBgABNQAECgQIBQADAAAAAA==.Orwasitme:BAAANQAECgQIBQAAAA==.Orwasitmii:BAAANQADCgMJAwABNQAECgQIBQADAAAAAA==.',
Pa='Paladinii:BAAANQAECgUIBQAAAA==.',
Ph='Philonk:BAABNQAECn8fAAIFAAkKgRC6JgDtAQAFAAkKgRC6JgDtAQAAAA==.',
Pj='Pjxyo:BAAANQAECgYIEwAAAA==.',
Po='Polytots:BAACNQAFFH8RAAMQAAYKFg7RDgBiAQAQAAYKFg7RDgBiAQACAAIKcwkNJwCQAAA1AAQKfz0AAxAACgoHI/4BAMgDABAACgoHI/4BAMgDAAIAAwpIEB1lAHAAAAAA.',
Ps='Psycototem:BAAANQAECgMIBwAAAA==.',
Ra='Razius:BAAANQAECggIDgAAAA==.',
Re='Rebexha:BAABNQAECn8ZAAMZAAYKUwpUXgDFAAAZAAYKeQdUXgDFAAAWAAQKCwjeQgC5AAAAAA==.Recoiless:BAAANQADCgYICAAAAA==.Replayjade:BAAANQADCgEIAQAAAA==.',
Ri='Ricklepick:BAAANQAECgcICgABNQAFFAIIBgAEAEUTAA==.',
Ro='Romaeus:BAAANQADCgYIBwAAAA==.',
Ry='Ryzenther:BAAANQAECgIJAwAAAA==.',
['Rà']='Ràgnar:BAAANQAECgMIAgAAAA==.Ràgñar:BAAANQADCgYIEQAAAA==.',
Sc='Scarpa:BAAANQAECgEIAQABNQAECgoKNAABAHgUAA==.Scathclipe:BAABNQAECn8nAAMSAAkKQxaELgAqAgASAAkKrxKELgAqAgAaAAgKvxT/CAAEAgAAAA==.',
Se='Sealedfate:BAAANQAECgEIAQAAAA==.Seancodi:BAAANQAECgEIAQABNQAFFAYIFQAHAPIdAA==.Senomage:BAABNQAECn8kAAMbAAoKcyJbNgAcAwAbAAoKcyJbNgAcAwAcAAMK/R35HwDqAAAAAA==.Serphentos:BAAANQABCgIIAgAAAA==.',
Sh='Shasato:BAABNQAECn8nAAMdAAoKrhwHBgAzAwAdAAoKrhwHBgAzAwABAAQKVAwSLgCoAAAAAA==.Shazrast:BAAANQADCgQIBAAAAA==.Shockss:BAAANQAECgYICwAAAA==.',
Si='Sidie:BAAANQADCgMIAwAAAA==.Sindora:BAAANQADCgEIAQAAAA==.Sizouze:BAABNQAECn8qAAIMAAoKxwvBKgBSAQAMAAoKxwvBKgBSAQAAAA==.',
Sk='Skyepic:BAACNQAFFH8hAAMeAAcKUh2XAgCAAgAeAAcKUh2XAgCAAgAfAAEKTgWlEQA+AAA1AAQKfyYAAh4ACQp+JhQBAOMDAB4ACQp+JhQBAOMDAAAA.Skylight:BAAANQAECggIDAAAAA==.',
Sn='Sneakfu:BAABNQAECn8oAAMSAAgKuRVbMwAPAgASAAgKjxBbMwAPAgAgAAcKaBacHQDmAQAAAA==.Snugwalnut:BAACNQAFFH8QAAIQAAYK6RDgCADDAQAQAAYK6RDgCADDAQA1AAQKfy0AAhAACgqkH4g0AI0CABAACgqkH4g0AI0CAAAA.',
So='Soejoedi:BAABNQAECn80AAIBAAoKeBQ8EABYAQABAAoKeBQ8EABYAQAAAA==.Sorrowin:BAAANQABCgIIAgAAAA==.',
Sp='Spicyburrito:BAAANQAECgIIAgAAAA==.',
St='Stitchzpls:BAAANQAECgIIBAAAAA==.',
Ta='Taintedrush:BAACNQAFFH8JAAIhAAUK+wWcAADKAAAhAAUK+wWcAADKAAA1AAQKfy4AAiEACgqEGRwDANMCACEACgqEGRwDANMCAAAA.Tarhostamir:BAAANQAECgQIBQAAAA==.Taurup:BAAANQADCgYIEAABNQAFFAQICQAGAAkIAA==.Tazz:BAABNQAECn8aAAMIAAcK4QLa6gArAQAIAAcK4QLa6gArAQAJAAEKAABwoAAaAAAAAA==.',
Te='Teenjus:BAAANQADCgcICQAAAA==.',
Th='Thaluus:BAAANQADCgUICQAAAA==.Thanossnap:BAAANQABCgQIBgABNQAECgoKNAAEAIAbAA==.Thaysinga:BAABNQAECn8mAAIKAAkKShJnDAB+AQAKAAkKShJnDAB+AQAAAA==.Thelandlord:BAAANQAECgIIAgAAAA==.Thunderblast:BAAANQAECgcIDgAAAA==.Thuss:BAAANQADCgQIBAAAAA==.',
To='Totemtosser:BAAANQAECgEIAQAAAA==.',
Tr='Trollor:BAAANQADCggIHQAAAA==.',
Ut='Utzon:BAAANQADCgQJBAABNQAECgoKNAABAHgUAA==.',
Va='Vaedan:BAAANQADCgcIEQAAAA==.Valkyrrie:BAAANQADCgUIBQABNQADCggIFwADAAAAAA==.Vander:BAABNQAECn8ZAAMMAAYKkh99DQATAgAMAAYKkh99DQATAgANAAEKAABnjwAbAAAAAA==.Vannder:BAAANQAECgEIAgABNQAECgYIGQAMAJIfAA==.Vayper:BAABNQAECn84AAQNAAoKJSDDBgBsAwANAAoKJSDDBgBsAwAMAAIK4gop4wB/AAAiAAEK8gRELwAmAAAAAA==.Vaypshawk:BAAANQADCggIFAABNQAECgoKOAANACUgAA==.',
['Vë']='Vënöm:BAAANQAECgEIAQABNQAECgkJIQAWAN8ZAA==.',
Wa='Waggo:BAABNQAECn8hAAICAAcKrBAWgwCdAQACAAcKrBAWgwCdAQAAAA==.Waken:BAAANQAECgUICQAAAA==.Warm:BAAANQAFFAEIAQAAAA==.Waterboy:BAAANQADCgcIDAABNQADCgUIBgADAAAAAA==.',
We='Weemsy:BAAANQADCgYIBgAAAA==.Wellmet:BAAANQAECgEIAQAAAA==.',
Wi='Wildfire:BAACNQAFFH8JAAITAAYKABxFAAA9AgATAAYKABxFAAA9AgA1AAQKfzAAAhMACgqGJlIAANQDABMACgqGJlIAANQDAAAA.',
Wo='Wolfhammer:BAABNQAECn8wAAIVAAoKoRfzAQAMAgAVAAoKoRfzAQAMAgAAAA==.',
Wr='Wreckadin:BAABNQAECn8dAAIRAAoKRB3DQQDPAgARAAoKRB3DQQDPAgAAAA==.',
Ya='Yaztraz:BAABNQAECn8oAAMQAAkKLSAUPwBkAgAQAAgKxh8UPwBkAgACAAYKPgnhrgA1AQAAAA==.',
Ye='Yellowflag:BAAANQAECggIEQAAAA==.',
Za='Zarturion:BAAANQAECgIIAQAAAA==.',
Zo='Zod:BAACNQAFFH8JAAMGAAQKCQggAwC7AAAGAAQKCQggAwC7AAAXAAEKQQJCEQAyAAA1AAQKfzUAAwYACgrIF8YEALACAAYACgrIF8YEALACABcABAoQC+grAMUAAAAA.',
['Às']='Àsh:BAABNQAECn8ZAAIMAAoKfhHyMwAvAQAMAAoKfhHyMwAvAQAAAA==.',
['Év']='Évangeline:BAAANQAECgUIBgABNQAECggIKwAMAAYRAA==.',
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
