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

local lookup = {'Unknown-Unknown','Druid-Guardian','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Paladin-Holy','Priest-Holy','Priest-Discipline','Paladin-Retribution','Shaman-Elemental','Warrior-Arms','Paladin-Protection','Shaman-Restoration','Warrior-Protection','Mage-Fire','DeathKnight-Blood','DeathKnight-Frost','Hunter-Survival','Druid-Feral','Warlock-Demonology','Warlock-Destruction','Druid-Balance','Rogue-Outlaw','Priest-Shadow','DemonHunter-Devourer','DeathKnight-Unholy','Mage-Arcane','Mage-Frost','Shaman-Enhancement','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Monk-Windwalker','Monk-Mistweaver','Warrior-Fury','Evoker-Augmentation',}
local provider = {region='US',realm='Moonrunner',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abris:BAAANQAECgEIAQABNQAECgMIBAABAAAAAA==.',
Ac='Acekith:BAAANQABCgMIAwABNQAECgQJBgABAAAAAA==.Acense:BAAANQAECgQJBgAAAA==.Acidhunter:BAAANQADCgcIBwAAAA==.Acidlock:BAAANQAECgcIDAAAAA==.Acidpriest:BAAANQAECgQIBgAAAA==.',
Ad='Adacey:BAAANQAECgUICQAAAA==.Adragon:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Adrenalized:BAAANQADCgMIBAAAAA==.',
Ae='Aesuga:BAAANQADCgYIBgAAAA==.',
Ak='Aktras:BAAANQAECgQIDQAAAA==.',
Al='Alaunu:BAABNQAECoEfAAICAAgK+g82GACqAQACAAgK+g82GACqAQAAAA==.Alexx:BAAANQAECgQIBAAAAA==.Alkaid:BAAANQAECgYIDQAAAA==.Alunariel:BAAANQADCgUICgAAAA==.',
An='Anari:BAAANQAECgQJBwABNQAECggIDQABAAAAAA==.Anarky:BAAANQAECggICAAAAA==.Annebonny:BAAANQAECgQIBwAAAA==.',
Ap='Apsalar:BAAANQADCgcJBwAAAA==.',
Ar='Archdemon:BAABNQAECoE2AAMDAAkKjB7DEgDrAgADAAkK5BzDEgDrAgAEAAcK2R3NBwBWAgAAAA==.Arienys:BAAANQADCgYICwAAAA==.Arigosa:BAAANQADCgYIBwAAAA==.Ariis:BAAANQADCgUICQAAAA==.Arkh:BAAANQADCgMIAwAAAA==.Arkhanx:BAAANQADCgUJBQAAAA==.Arkhfu:BAAANQAECgIIAgAAAA==.Arleen:BAAANQADCgEIAQAAAA==.Arquen:BAAANQAECgYIEwAAAA==.Artemisia:BAAANQADCgYIDgAAAA==.',
As='Asheril:BAAANQADCgYICQAAAA==.Asian:BAAANQADCgIIAgAAAA==.Asra:BAAANQAECgUICQAAAA==.Astrov:BAAANQAECgYIEQAAAA==.',
At='Atulmags:BAAANQAECgYICQAAAA==.',
Au='Auani:BAABNQAECoEpAAIFAAgKsSI0CgAKAwAFAAgKsSI0CgAKAwAAAA==.Aurelily:BAAANQADCgYJDAAAAA==.Ausia:BAAANQAECgIIAgAAAA==.',
Az='Azazyl:BAAANQADCgQIDAAAAA==.Azzeus:BAAANQAECgMIBgABNQAECggIHgAGADMSAA==.Azzshot:BAABNQAECoEeAAMGAAgKMxKnbgAIAgAGAAcKiRSnbgAIAgAHAAgKWQMrPABBAQAAAA==.',
Ba='Babyrinsjr:BAAANQAECgMIBgAAAA==.Badista:BAAANQADCgIIAgAAAA==.Balleont:BAABNQAECoEdAAIGAAgKPxKFXwAuAgAGAAgKPxKFXwAuAgAAAA==.Barrada:BAAANQAECgUIEAAAAA==.',
Be='Beefcakeßody:BAAANQADCgYIBgAAAA==.Berea:BAABNQAECoEvAAMIAAYK0gslSABcAQAIAAYK0gslSABcAQAJAAUKsgPKNQDoAAAAAA==.',
Bl='Blankdemonic:BAAANQABCgYICAAAAA==.Blankwar:BAAANQADCgUIBQAAAA==.Bleedblue:BAAANQAECgYIDwAAAA==.Blitzed:BAAANQADCgIIAgAAAA==.Bloodhaven:BAAANQADCgEIAQAAAA==.',
Bo='Bo:BAABNQAECoEpAAIGAAgKHyDWKADVAgAGAAgKHyDWKADVAgAAAA==.Bobbinrobin:BAAANQAECgQIBQABNQAECgcIBwABAAAAAA==.Borahae:BAAANQAECgQICAABNQAECggIIAAKAJMFAA==.Borden:BAAANQADCgQJBAAAAA==.',
Br='Bradent:BAAANQADCggIGgAAAA==.Breach:BAAANQAECgIIAwAAAA==.Brunnhild:BAAANQAECgIIAgAAAA==.Bryxi:BAAANQAECgEIAQAAAA==.Brünhilde:BAABNQAECoEdAAMLAAkKHBDSSQAhAgALAAkK2g7SSQAhAgAMAAQKAxABEwDdAAAAAA==.',
Bs='Bstbll:BAACNQAFFIEQAAIFAAUK2Rn3BACrAQAFAAUK2Rn3BACrAQA1AAQKgSYAAgUACQpnHfUOAMgCAAUACQpnHfUOAMgCAAAA.',
Bu='Bubbleheals:BAABNQAECoEcAAMKAAgKNwr9eACFAQAKAAgKNwr9eACFAQANAAEKmhECbgE4AAABNQAECgkJMAAOAF8cAA==.Bundtcake:BAAANQAECggIBwAAAA==.Burningfist:BAAANQAECgMIBgAAAA==.Buttsnacks:BAABNQAECoEaAAIPAAcKLxhucwAZAgAPAAcKLxhucwAZAgAAAA==.',
Ca='Caletha:BAAANQADCgYICwAAAA==.Callistrah:BAAANQAECgQIBgAAAA==.Caltaa:BAABNQAECoEpAAIQAAgKpCLJBwALAwAQAAgKpCLJBwALAwAAAA==.Canarah:BAAANQADCgQIBAABNQAECgkJGgARAJIZAA==.Canverian:BAAANQAECgMIBgAAAA==.Captsmash:BAABNQAECoEWAAISAAgKWBbqDgAQAgASAAgKWBbqDgAQAgAAAA==.Carmedic:BAAANQADCgIIAgAAAA==.Caudel:BAAANQABCgIIAgAAAA==.',
Cd='Cdub:BAAANQAECgYIDQAAAA==.',
Ch='Charcuterie:BAAANQAECgQICwAAAA==.Chasseurfool:BAAANQAECgQICQAAAA==.Chat:BAABNQAECoEpAAIOAAkKyxtcKwCuAgAOAAkKyxtcKwCuAgAAAA==.Chevre:BAAANQAECgQIDwAAAA==.Chezaro:BAAANQAECgYIDwAAAA==.Chickenwing:BAABNQAECoEaAAITAAcKVCBrAQCEAgATAAcKVCBrAQCEAgAAAA==.Christano:BAAANQAECgYIDQAAAA==.Christhecold:BAABNQAECoEaAAIPAAgKDhiyagAxAgAPAAgKDhiyagAxAgAAAA==.Chrollo:BAAANQAECgQICwAAAA==.Chumba:BAAANQAECgYIDQAAAA==.',
Ci='Cinnamilk:BAAANQAECgMIAwABNQAECgkJKAAUAHwYAA==.',
Cl='Clamslamm:BAEANQADCgUIBQABNQAECgcIHwAVAF4hAA==.Cloudcrack:BAECNQAFFIENAAMRAAQKAg/ADgAzAQARAAQKAg/ADgAzAQAOAAMKdArjFgDeAAA1AAQKgSUAAw4ACQpsHcEjANgCAA4ACQpsHcEjANgCABEACAqRHYM2AF4CAAAA.',
Co='Cocotaso:BAAANQABCgIIAgAAAA==.Codemon:BAAANQAECgUIEAAAAA==.Cole:BAAANQADCgUIBQAAAA==.Cosmoline:BAABNQAECoEXAAIWAAkKCxSqAwCkAgAWAAkKCxSqAwCkAgABNQAECgYIEwABAAAAAA==.Cotw:BAAANQADCgQIBAABNQAECgUICgABAAAAAA==.Coverttops:BAAANQAECgUICQAAAA==.',
Cp='Cptcharis:BAAANQADCgEIAQAAAA==.',
Cr='Critmyshorts:BAAANQADCggICAAAAA==.Critnespears:BAAANQADCgYIBgAAAA==.',
Cu='Cubann:BAAANQAECgIIAgAAAA==.',
Cy='Cylrhea:BAAANQAECgUIDwAAAA==.Cynri:BAAANQADCgQIBQABNQAECgIIAgABAAAAAA==.Cyntrill:BAAANQAECgIIAgAAAA==.',
Da='Daboulder:BAAANQAECgEIAQAAAA==.Dadderz:BAAANQADCgYIEwAAAA==.Dagnome:BAAANQADCggICAAAAA==.Dahunter:BAAANQAECgIIAgAAAA==.Dajoel:BAAANQAECgIIAgAAAA==.Dalacia:BAAANQAECgYIDQAAAA==.Darkhollow:BAAANQADCgcIBwAAAA==.Darknature:BAABNQAECoEfAAIFAAgKJRWjHAAjAgAFAAgKJRWjHAAjAgAAAA==.Darkodin:BAAANQAECgUIDwAAAA==.Darkshamy:BAAANQAECgEIAQAAAA==.Darksknightt:BAAANQADCgEIAQAAAA==.Darrad:BAAANQAECgUIBwAAAA==.Datnagadrake:BAACNQAFFIEHAAIPAAMKgRCWHQDfAAAPAAMKgRCWHQDfAAA1AAQKgTgAAw8ACQrTH4AqAAADAA8ACQqhHoAqAAADABIABgpuIPkMADgCAAAA.Dawinchy:BAABNQAECoEiAAMFAAgKxhkTGwA1AgAFAAgKxhkTGwA1AgAXAAUK/RLBGAA3AQAAAA==.',
De='Deadlypsycho:BAAANQAECgEIAQAAAA==.Deathavoider:BAAANQADCggICgAAAA==.Deathawakens:BAAANQADCgEIAQAAAA==.Deathlyill:BAAANQAECgIJAgAAAA==.Decemberr:BAAANQAECgQICQAAAA==.Dekudin:BAAANQAECgYIDQAAAA==.Dellistia:BAAANQADCgYICwAAAA==.Dennywenny:BAAANQAECgUIDAAAAA==.Deric:BAAANQADCgMIAwAAAA==.Desdamona:BAAANQAECgQICAAAAA==.Destrodemon:BAAANQADCggICAAAAA==.Destropally:BAABNQAECoEcAAINAAgKuhB5iwDbAQANAAgKuhB5iwDbAQAAAA==.Devorick:BAABNQAECoElAAMYAAgKnxnCRABnAgAYAAgKnxnCRABnAgAZAAIK9QM4ZQBMAAAAAA==.',
Di='Diaval:BAAANQADCgYIEQAAAA==.Dih:BAAANQADCgYIBgABNQAECggIIgAZAKMXAA==.Dijarl:BAAANQAECgcIDgAAAA==.Dipndots:BAAANQAECgIIAgAAAA==.Dirtyboy:BAAANQADCgIIAgAAAA==.Diyiya:BAAANQAECgUICwAAAA==.',
Do='Doorki:BAAANQADCggIDwAAAA==.Dottey:BAAANQAECgUIDQAAAA==.Doubleott:BAAANQAECgEIAQAAAA==.',
Dr='Drael:BAAANQAECgMIBQAAAA==.Draickin:BAABNQAECoEaAAIKAAcKPRaEVgD1AQAKAAcKPRaEVgD1AQAAAA==.Drekle:BAAANQAECgMICQABNQAECgcIHgAaAN8UAA==.Drelian:BAAANQAECgIIAgAAAA==.Drevy:BAABNQAECoETAAIbAAcKVRlkBwApAgAbAAcKVRlkBwApAgAAAA==.Drewdox:BAAANQADCgUJDAAAAA==.Drewsguy:BAAANQADCgYIEwAAAA==.Drexchan:BAAANQAECgEIAQAAAA==.Drizzlenuts:BAAANQAECgcIBwABNQAECgcIEAABAAAAAA==.Drrabbít:BAAANQADCgQIBAAAAA==.Drumira:BAAANQADCgMIAwABNQAECgkJHQAcALIRAA==.Drumk:BAAANQADCgIIAgABNQAECgkJHQAcALIRAA==.Drumma:BAAANQADCgcIBwAAAA==.Drummer:BAABNQAECoEdAAQcAAkKshGTLgCIAQAcAAcKdA2TLgCIAQAMAAUKrhQvDgA3AQALAAUKkgXUpADrAAAAAA==.Drumroleplz:BAAANQADCggICAABNQAECgkJHQAcALIRAA==.',
Dw='Dw:BAABNQAECoEYAAMdAAgK6xqgFwCIAgAdAAgK6xqgFwCIAgADAAMKqw/EZwCmAAABNQAECgkJHgAGANMhAA==.',
['Dà']='Dàddybear:BAAANQAECggIBAAAAA==.',
Ea='Earthsangel:BAAANQAECgQIBAAAAA==.',
Ec='Eclair:BAAANQAECgQICQAAAA==.',
Ed='Edralyia:BAAANQADCgYICwAAAA==.',
Eg='Egwene:BAAANQADCgQIBAAAAA==.',
Ei='Eilaurosa:BAAANQAECgcIEgAAAA==.',
El='Eldrinne:BAAANQAECgYIEgAAAA==.Eleblast:BAAANQAECgIIAgAAAA==.Elizavoid:BAABNQAECoEWAAMLAAgK1hkaPgBNAgALAAgK1hkaPgBNAgAcAAEKHweCeQAjAAAAAA==.Elizawrath:BAAANQADCgIIAgAAAA==.Elkuco:BAAANQAECgEIAQAAAA==.Elmindreyda:BAAANQAECgMIBgAAAA==.Elthiss:BAABNQAECoEhAAICAAcKABpsEgD4AQACAAcKABpsEgD4AQAAAA==.',
En='Enfer:BAAANQADCgUIBQABNQAECgkJKQAOAMsbAA==.',
Er='Erequois:BAAANQADCgEIAQABNQAECgEIAQABAAAAAA==.Erianthe:BAABNQAECoEaAAIeAAgKPgQfeAAQAQAeAAgKPgQfeAAQAQAAAA==.Erophien:BAAANQADCgMIBAAAAA==.Erovynael:BAAANQAECgQICAAAAA==.Erovynthalin:BAAANQADCgYIEAAAAA==.Errorwing:BAAANQADCggICAAAAA==.',
Es='Eshera:BAAANQADCgIIAgAAAA==.Esherä:BAAANQAECgEIAQAAAA==.',
Ev='Eversong:BAAANQADCgYIDAAAAA==.',
Fa='Faewhisker:BAAANQAECgcIDgAAAA==.Faithfool:BAABNQAECoEZAAIOAAgKVAnzbwCgAQAOAAgKVAnzbwCgAQAAAA==.Fancyfeet:BAAANQAECgUIBQABNQAECgkJFwAJAB8UAA==.Fanduelfiend:BAAANQADCgMIAwAAAA==.Fangmonarch:BAAANQADCgUIBQAAAA==.Fashaladd:BAABNQAECoEeAAMaAAcK3xSjQgC+AQAaAAcKmhOjQgC+AQACAAEKJhv6RgBJAAAAAA==.',
Fe='Fearios:BAABNQAECoEoAAIUAAkKfBjmJwBlAgAUAAkKfBjmJwBlAgAAAA==.Felbeast:BAAANQAECgMIBQAAAA==.Felbound:BAAANQADCgUICQAAAA==.Femboy:BAAANQADCggICAAAAA==.Feorar:BAAANQADCgYJBgAAAA==.Feta:BAAANQAECgYICgABNQAECggIDQABAAAAAA==.',
Fi='Fieldtrip:BAAANQAECgIIAwAAAA==.Fiendfyre:BAAANQADCgUIBQAAAA==.Fizzlenuts:BAAANQAECgcIEAAAAA==.',
Fl='Flightless:BAAANQADCggICgAAAA==.',
Fo='Foxi:BAAANQAECgQJBAAAAA==.',
Fr='Frosttbyte:BAABNQAECoEqAAMfAAgK+hljcQCFAgAfAAgK+hljcQCFAgAgAAEKVxlcNwBIAAAAAA==.Frostytute:BAAANQADCgIIAgAAAA==.',
Fu='Fullmetalass:BAAANQAECgYIEgAAAA==.',
Fy='Fyyre:BAAANQADCgEIAQAAAA==.',
['Fë']='Fëiróx:BAAANQADCgIIAgAAAA==.',
Ga='Galistar:BAAANQAECgMIBQAAAA==.Garrotxa:BAAANQAECggICAABNQAECggIDQABAAAAAA==.',
Ge='Gevallen:BAAANQAECgYIBwAAAA==.',
Gh='Ghavinental:BAABNQAECoEWAAMOAAYKgA9mhQBmAQAhAAYKFQoZHABrAQAOAAYKhQ5mhQBmAQAAAA==.',
Gi='Gil:BAAANQAECgcIEgAAAA==.Gilgamesh:BAAANQAECgUICgABNQAECgcIEgABAAAAAA==.',
Gl='Glizzard:BAAANQAECgUICwABNQAECgYIEQABAAAAAA==.Glocket:BAAANQAECgIJBAAAAA==.Gloom:BAAANQAECgYIBgAAAA==.',
Gn='Gnolan:BAAANQAECgUIDQAAAA==.',
Go='Goatspace:BAABNQAECoEYAAQGAAcKRgdYsQBtAQAGAAcK6gZYsQBtAQAHAAQKcgL9YAB8AAAWAAEKAAELEwAbAAAAAA==.Gomu:BAAANQADCgQIBAAAAA==.Gongagà:BAABNQAECoEfAAIdAAcKsxDsKwDBAQAdAAcKsxDsKwDBAQAAAA==.Goodwithabow:BAAANQAECgQICAAAAA==.Goremaster:BAAANQAECgQJCgAAAA==.Gothbaddie:BAAANQAECgQIBAABNQAECggIDQABAAAAAA==.Goyum:BAAANQADCgEIAQAAAA==.',
Gr='Grankino:BAABNQAECoEfAAMXAAcKUg9bGQAwAQAaAAcKbAjmWQBCAQAXAAUKARNbGQAwAQAAAA==.Greedisgood:BAAANQADCgMIAwAAAA==.Greenthumbs:BAAANQADCgYIBgAAAA==.',
Gw='Gwaelphypha:BAABNQAECoEZAAIUAAYKXBl9SgCuAQAUAAYKXBl9SgCuAQABNQAECgEIAQABAAAAAA==.',
Ha='Hakarii:BAAANQADCgEIAQAAAA==.Halder:BAAANQAECgEIAQAAAA==.Hapkido:BAABNQAECoEpAAIiAAgKRSRLAwBJAwAiAAgKRSRLAwBJAwAAAA==.Hauwitzer:BAAANQADCgYIBQAAAA==.Hawk:BAAANQAECgMIAwAAAA==.Hazrek:BAABNQAECoEVAAIhAAcKjQt1FwDDAQAhAAcKjQt1FwDDAQAAAA==.',
He='Hecate:BAAANQAECgMIBQAAAA==.Heidnik:BAAANQAECgUIBQAAAA==.Heihei:BAAANQAECgQIBwAAAA==.Heneedsumilk:BAAANQADCgYICgAAAA==.Heretic:BAAANQAECgIIAgAAAA==.',
Hi='Hillboy:BAAANQADCggIDgAAAA==.',
Ho='Holydes:BAAANQAECgIIAgABNQAECgQICAABAAAAAA==.Holytrinityy:BAAANQADCgYIBgAAAA==.Hooch:BAAANQAECgMIAwABNQAECgQICQABAAAAAA==.',
Hu='Humboldt:BAAANQAECggIBAABNQAECggIDQABAAAAAA==.Huunaron:BAAANQAECgYICwAAAA==.',
['Hé']='Héx:BAACNQAFFIEZAAMfAAcKXBfhBwAkAgAfAAYKuxnhBwAkAgAgAAEKIgntCgBWAAA1AAQKgRkAAh8ACQpMGnSBAGMCAB8ACQpMGnSBAGMCAAAA.',
Id='Idylwilde:BAAANQAECgQIBgAAAA==.',
Ie='Ienzo:BAAANQADCgQIBwAAAA==.',
Ih='Iheartoreos:BAABNQAECoEYAAIUAAYKTBbwUgCGAQAUAAYKTBbwUgCGAQAAAA==.',
Il='Iloveoreos:BAAANQADCgYIBgAAAA==.',
In='Instakill:BAAANQADCgQIBAAAAA==.Intent:BAAANQADCgMIAwAAAA==.Invictae:BAAANQAECgIIBAAAAA==.',
Io='Iobo:BAACNQAFFIEOAAIdAAYKlSAlAgBQAgAdAAYKlSAlAgBQAgA1AAQKgSEAAh0ACQriI6sFAHEDAB0ACQriI6sFAHEDAAAA.',
Ir='Irk:BAAANQADCggICAAAAA==.Ironic:BAAANQADCgYIBgABNQAECggIKAAIAEchAA==.',
Ja='Jagaerr:BAAANQABCgUICQAAAA==.Jarco:BAEANQAECgEIAQABNQAFFAYICwAbALMVAA==.Jasseca:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.',
Je='Jeandarc:BAAANQADCggICAAAAA==.Jezäbelle:BAAANQADCgYIDgAAAA==.',
Jo='Joesh:BAAANQABCgUICgAAAA==.',
Ka='Kaadra:BAAANQAECgUIBQAAAA==.Kaelkin:BAABNQAECoEdAAMLAAgKFhTDVQD0AQALAAgKFhTDVQD0AQAMAAIK6gZkHgBZAAAAAA==.Kaelun:BAAANQADCgcICwABNQAECggIHQALABYUAA==.Kaelundrus:BAAANQAECgQICgABNQAECggIHQALABYUAA==.Kainis:BAAANQAECgMIAwAAAA==.Kamonorin:BAAANQABCgIIAgAAAA==.Karmus:BAAANQADCgUJCAAAAA==.',
Ke='Keadin:BAAANQADCgYICwAAAA==.Keilas:BAAANQAECgUIEgAAAA==.Kerron:BAAANQAECgEIAQAAAA==.Keylala:BAAANQAECgQIBQAAAA==.',
Ki='Kickenmage:BAAANQADCgQIBAABNQAECgQICQABAAAAAA==.Kickentail:BAAANQAECgQICQAAAA==.Kiegh:BAAANQABCgQIBAAAAA==.Kior:BAAANQADCgYIBwAAAA==.Kirisham:BAAANQADCgMIAwAAAA==.Kiriwar:BAABNQAECoErAAIPAAkKuyFEHQA1AwAPAAkKuyFEHQA1AwAAAA==.Kirlia:BAAANQAECgUIEwAAAA==.',
Kl='Klymax:BAAANQAECgYIBwAAAA==.',
Ko='Kowkowkachoo:BAAANQAECgIIAgAAAA==.',
Kr='Krellis:BAAANQAECgEIAQAAAA==.Krisp:BAABNQAECoEqAAIfAAkKFCMKEQCKAwAfAAkKFCMKEQCKAwAAAA==.Krobelus:BAABNQAECoEaAAINAAgKYwXCyABQAQANAAgKYwXCyABQAQAAAA==.',
Ks='Ksharp:BAAANQADCgYIBgABNQAECgUIDgABAAAAAA==.',
Kv='Kvedadormu:BAAANQADCgYIEQAAAA==.Kvedeitrormr:BAAANQAECgEIAQAAAA==.Kvedfróðleik:BAAANQABCgEIAQAAAA==.Kvedærilaz:BAAANQADCgEIAQAAAA==.',
Ky='Kylearean:BAAANQADCgMJAwAAAA==.Kyran:BAAANQAECgIIAgAAAA==.',
['Kè']='Kèrónos:BAAANQAECgMIBQAAAA==.',
['Kì']='Kìllstheweak:BAABNQAECoEZAAIVAAgKgAhuQgB1AQAVAAgKgAhuQgB1AQAAAA==.',
La='Laeythe:BAEANQAECgQIBAABNQAECgkJKgALAK4lAA==.Lannah:BAAANQADCgYIDgAAAA==.Lash:BAAANQAECgMIBQAAAA==.',
Lc='Lclc:BAAANQAECgMIAwAAAA==.',
Le='Leafeon:BAAANQAFFAQIBAABNQAFFAcIEAARADkaAA==.Lebrin:BAAANQAECgQIDwAAAA==.Legaia:BAABNQAECoEoAAIPAAgK1SBsMwDeAgAPAAgK1SBsMwDeAgAAAA==.Legendknewl:BAAANQAECgQIBAAAAA==.Leliel:BAAANQADCggICAABNQAECgkJHgAKAHUaAA==.Lennyzamwam:BAAANQAECgQIBAAAAA==.Lesindre:BAAANQADCgcIDQABNQAECggIAQABAAAAAA==.Letaria:BAAANQADCgYIBgAAAA==.Lexapro:BAAANQAECgQIBAAAAA==.',
Li='Lianissa:BAAANQADCggIDwAAAA==.Lillinna:BAAANQAECgQIBwAAAA==.Lithlina:BAAANQADCgYIBgAAAA==.',
Lo='Loamein:BAAANQAECgcIDQAAAA==.Lockrocks:BAAANQAECgYICwAAAA==.Lockycharmz:BAAANQAECgEIAgABNQAECgkJKAAUAHwYAA==.Lorcán:BAAANQADCgYICwAAAA==.Lormazlezrax:BAABNQAECoEaAAIRAAkKkhmROQBRAgARAAkKkhmROQBRAgAAAA==.',
Lu='Lucernyx:BAAANQAECgIIAgAAAA==.Luckystars:BAAANQADCgQIBAAAAA==.Luis:BAAANQADCgQIBAAAAA==.Luminara:BAAANQADCgYIBgAAAA==.Lunaera:BAAANQAECgUIBwAAAA==.Lune:BAAANQADCgcIBwABNQAECgIIAgABAAAAAA==.Lunella:BAAANQADCgYIBgABNQAECgIIAgABAAAAAA==.Lunellia:BAAANQAECgIIAgAAAA==.Lunevra:BAAANQABCgcIBwABNQAECgIIAgABAAAAAA==.Lupi:BAAANQADCggIDwAAAA==.Lurkaburger:BAABNQAECoEZAAIPAAkKABYCUwB1AgAPAAkKABYCUwB1AgAAAA==.',
Ly='Lythindra:BAAANQADCgQIBAAAAA==.',
Ma='Madhatter:BAAANQAECgMICAAAAA==.Mageistmage:BAACNQAFFIEMAAIfAAUK2xaPFgCbAQAfAAUK2xaPFgCbAQA1AAQKgRkAAh8ACQqBI0E4AAoDAB8ACQqBI0E4AAoDAAAA.Magori:BAAANQADCgYIBgAAAA==.Majarl:BAAANQAECgYIEgAAAA==.Maki:BAAANQADCgEIAQABNQAECgUIEAABAAAAAA==.Malegar:BAAANQADCgYIFAAAAA==.Malificent:BAAANQADCggIDgAAAA==.Mammajamma:BAABNQAECoEgAAIaAAgKNhNJNwAJAgAaAAgKNhNJNwAJAgAAAA==.Marsvolta:BAAANQAECgQICAAAAA==.Maruxus:BAABNQAECoEoAAIIAAgK9BamIgBEAgAIAAgK9BamIgBEAgAAAA==.Marwen:BAAANQADCgYICwAAAA==.Maulsin:BAAANQADCgUIBQAAAA==.Mavanthia:BAABNQAECoEaAAIPAAgK7hCSiADhAQAPAAgK7hCSiADhAQAAAA==.',
Mc='Mcdeathy:BAAANQAECgUICgAAAA==.Mclardragos:BAABNQAECoEcAAMjAAkKuSJvBABhAwAjAAkKuSJvBABhAwAkAAEKUggXOgAwAAAAAA==.',
Me='Meadõw:BAAANQADCgUIBQAAAA==.Meatshield:BAAANQADCgcIDAAAAA==.Mecharoni:BAABNQAECoEoAAMIAAgKRyFrGQCJAgAIAAcK7iBrGQCJAgAJAAYKbh8LGwDsAQAAAA==.Meganaturexl:BAAANQABCgQIBAAAAA==.Megashamxl:BAAANQABCgQIBAAAAA==.Mendication:BAAANQAECgcIDAAAAA==.Meretrixee:BAAANQADCgIIAgABNQAECggIJgALALwWAA==.Meteion:BAAANQAECgQIBAABNQAECggIAQABAAAAAA==.',
Mi='Miacyn:BAAANQAECgIIBQAAAA==.Miladybast:BAAANQAECgUICwAAAA==.Minke:BAAANQADCggIDwAAAA==.Mirra:BAAANQAECgYIDgAAAA==.Missdorei:BAAANQADCgUIBQAAAA==.',
Mo='Momsrymommy:BAAANQAECgUICgAAAA==.Moonaurora:BAAANQABCgMIAwAAAA==.Moontater:BAAANQADCgYIBgAAAA==.Mordekaiser:BAAANQADCggICAAAAA==.Morionso:BAAANQAECgUIDAAAAA==.Morphyrinsjr:BAAANQADCgcIBwABNQAECgMIBgABAAAAAA==.Mortarion:BAABNQAECoEnAAMeAAgKfhqbPAAIAgAeAAcKCxubPAAIAgAVAAcKexFKPgCPAQAAAA==.Morwenspring:BAAANQADCgMIAwAAAA==.',
Ms='Mssrbubbles:BAAANQABCggJFAAAAA==.',
Mu='Murdiûs:BAABNQAECoEfAAMlAAcKhR+aFQB9AgAlAAcKhR+aFQB9AgAmAAEKkRf+QQBDAAAAAA==.',
My='Mythbruh:BAEBNQAECoEfAAMVAAcKXiE6LQD/AQAVAAcKQho6LQD/AQAeAAcKeCCeQQDvAQAAAA==.',
Na='Nachokru:BAAANQABCgEIAgAAAA==.Nahla:BAAANQAECgIIAgAAAA==.Namrevlis:BAAANQADCgIIAgABNQAECgkJHQAcALIRAA==.Narl:BAAANQAECgIIBQAAAA==.Nayrditation:BAAANQAECgcIDQAAAA==.Nayrlock:BAAANQAECgcICwABNQAECgcIDQABAAAAAA==.',
Nc='Nctee:BAAANQAECgUICgAAAA==.',
Ne='Necropally:BAAANQADCgcIDQAAAA==.',
Ni='Nightsmoke:BAAANQAECgMJBQAAAA==.',
No='Nolabull:BAAANQADCgQIBAAAAA==.Nonattarius:BAAANQAECgMIBgAAAA==.Noraelara:BAAANQAECggIAQAAAA==.Norezfou:BAABNQAECoEpAAMLAAgKYBYzSAAnAgALAAgKYBYzSAAnAgAcAAcKYBr+HwAUAgAAAA==.Norran:BAAANQADCgMIAwAAAA==.Notalice:BAAANQADCgYIBgABNQAECgMIBAABAAAAAA==.Nottartar:BAAANQAECgIJAgAAAA==.',
Nu='Nuker:BAAANQADCgYIEgAAAA==.Nurobi:BAABNQAECoEbAAIaAAgKmA2NQwC5AQAaAAgKmA2NQwC5AQAAAA==.',
Od='Odanobunaga:BAABNQAECoEjAAIPAAkKexpyTQCHAgAPAAkKexpyTQCHAgAAAA==.Odyn:BAAANQAECgMIBQAAAA==.',
Oe='Oerrael:BAAANQADCgcIEAAAAA==.',
Or='Oridk:BAABNQAECoEgAAIeAAgKgBwyLQBbAgAeAAgKgBwyLQBbAgABNQAECgkJJQAWAPUhAA==.Oripal:BAAANQADCgcICAABNQAECgkJJQAWAPUhAA==.Oríon:BAABNQAECoElAAQWAAkK9SFHBACBAgAWAAcKICNHBACBAgAGAAUKHxs8kQC1AQAHAAYKJxZDMwCIAQAAAA==.',
Pa='Pankratease:BAAANQAECgUIBwAAAA==.Pankratoes:BAAANQADCgQIBQABNQAECgUIBwABAAAAAA==.Pankratos:BAAANQADCgUIBQABNQAECgUIBwABAAAAAA==.Papahess:BAABNQAECoEaAAMaAAcKjBXhPwDRAQAaAAcKWRXhPwDRAQACAAMKIBCIOwCIAAAAAA==.Paradias:BAABNQAECoEXAAIJAAkKHxS+EgBGAgAJAAkKHxS+EgBGAgAAAA==.Pastor:BAAANQABCgIIAgAAAA==.Paxxul:BAAANQADCggICwAAAA==.',
Pe='Peppersham:BAAANQAECgMIBgAAAA==.Petespally:BAAANQAECgMIBQAAAA==.',
Pf='Pfftpfft:BAAANQAECgIIBAAAAA==.',
Ph='Pha:BAAANQAECgcIEgAAAA==.Phatdanny:BAAANQAECggIDAAAAA==.Phonycheese:BAABNQAECoEfAAMNAAgK3RZOewAEAgANAAcKmhlOewAEAgAKAAIKTwiq9ABaAAAAAA==.Phur:BAAANQAECgMIAwAAAA==.',
Pi='Pixen:BAABNQAECoEvAAIYAAkKFxrVMgCjAgAYAAkKFxrVMgCjAgAAAA==.',
Po='Pocalypse:BAAANQAECgQIBQAAAA==.Ponkeyfists:BAABNQAECoEhAAIlAAkKIiJYBgBYAwAlAAkKIiJYBgBYAwAAAA==.Portstar:BAABNQAECoEaAAIfAAgKbgfF3wCiAQAfAAgKbgfF3wCiAQAAAA==.Powderhorn:BAAANQADCgUIBQAAAA==.',
Pr='Pravium:BAAANQADCgYIBgABNQAECgIIBAABAAAAAA==.Primed:BAABNQAECoEoAAIXAAgK2BDiDgDpAQAXAAgK2BDiDgDpAQAAAA==.',
Pu='Pungla:BAAANQAECggICwAAAA==.',
Qu='Quelthanos:BAABNQAECoEdAAMNAAcKFhPXlADFAQANAAcKFhPXlADFAQAKAAEKfBAgAgE8AAAAAA==.',
Ra='Radical:BAAANQAECgMIBAAAAA==.Ralvick:BAAANQADCgEJAQAAAA==.Ramuun:BAAANQADCgIIAgAAAA==.Randomclown:BAAANQAECgEIAQAAAA==.Rascalfats:BAAANQAECgQIBwABNQAECgQICQABAAAAAA==.Rashii:BAAANQAECgYIEgAAAA==.Raworrior:BAAANQAECgUIEAAAAA==.',
Re='Reax:BAAANQADCgYIBgAAAA==.Rebaderchi:BAABNQAECoEhAAIdAAkKbRkXFQClAgAdAAkKbRkXFQClAgABNQADCgMIAwABAAAAAA==.Reignofpower:BAAANQADCgUIBQAAAA==.Remoria:BAAANQAECgUICwAAAA==.Renildan:BAAANQAECgYICgAAAA==.Rezputan:BAAANQADCggICAAAAA==.',
Rh='Rhavin:BAAANQAECgIIAgAAAA==.Rholand:BAABNQAECoEgAAIPAAkKyhobRgCeAgAPAAkKyhobRgCeAgAAAA==.',
Ri='Rivalt:BAAANQABCgMIAwAAAA==.Riverra:BAAANQADCgcICgAAAA==.Rizzoy:BAABNQAECoEYAAMnAAUKBRm5EQBhAQAnAAUKthi5EQBhAQAPAAIKQg79GAFsAAAAAA==.',
Ro='Rollo:BAAANQADCgIIBAAAAA==.Roottender:BAAANQADCgcICwAAAA==.Rovyr:BAABNQAECoEhAAMjAAcKjB6WEwBgAgAjAAcKjB6WEwBgAgAoAAEKlgQsIwAlAAAAAA==.Rowinna:BAAANQADCgUIBQAAAA==.',
Ru='Ruckabis:BAABNQAECoEYAAIRAAgKuhfHQQAvAgARAAgKuhfHQQAvAgAAAA==.',
Ry='Rybearkin:BAAANQADCgMIAwAAAA==.Rylos:BAAANQAECggIBQAAAA==.Ryshadow:BAAANQADCgYICwAAAA==.Ryumi:BAAANQAECgYJEgAAAA==.',
Sa='Saansula:BAAANQADCgEIAQAAAA==.Sacmaster:BAAANQADCggIDAABNQAECggIIgAZAKMXAA==.Saitamå:BAABNQAECoEfAAImAAcKJBlxFgDmAQAmAAcKJBlxFgDmAQAAAA==.Samanaras:BAABNQAECoEYAAMPAAgKrhD7jgDPAQAPAAgKyA77jgDPAQASAAYKIBHmHgAvAQAAAA==.Sangwyn:BAAANQADCgYIBgABNQAECgUIEAABAAAAAA==.Santiago:BAAANQADCgMIAwAAAA==.Saratoga:BAAANQAECgQICwAAAA==.Sarkana:BAABNQAECoEeAAIKAAkKdRrAIQDPAgAKAAkKdRrAIQDPAgAAAA==.Saxonn:BAAANQAECgIIAgAAAA==.Saydis:BAAANQAECgMIBAAAAA==.',
Sc='Scatterbrain:BAAANQADCgcIDAAAAA==.',
Se='Sebattan:BAAANQADCgYIBwAAAA==.Seleinai:BAAANQADCgMIAwABNQAECggIKQAMAG0dAA==.Seleine:BAABNQAECoEpAAIMAAgKbR0vAwCxAgAMAAgKbR0vAwCxAgAAAA==.Seloric:BAAANQAECgUIEAAAAA==.Serendrin:BAABNQAECoEgAAIIAAgK6B9nEQDSAgAIAAgK6B9nEQDSAgAAAA==.Sevalandre:BAAANQADCggICgABNQAECgEIAQABAAAAAA==.',
Sh='Shadowskyz:BAAANQAECgQIBwABNQAECgkJMAAOAF8cAA==.Shaggimaggi:BAAANQAECgUICwAAAA==.Shamanis:BAAANQADCgQIBAAAAA==.Shamina:BAABNQAECoEwAAIOAAkKXxyyIADrAgAOAAkKXxyyIADrAgAAAA==.Shamorex:BAABNQAECoEaAAIOAAcKDxxjRAA5AgAOAAcKDxxjRAA5AgAAAA==.Shatter:BAAANQAECgYIEQAAAA==.Shax:BAAANQADCggICAABNQAECgkJKgAfABQjAA==.Shlevin:BAAANQADCgcIDAAAAA==.',
Si='Sideshift:BAAANQAECgQIBAABNQAECgkJMAAOAF8cAA==.',
Sk='Skaarr:BAAANQADCgQIBQAAAA==.Skibidiheals:BAAANQAECgEIAQAAAA==.Skybear:BAAANQABCgYICAAAAA==.',
Sl='Slash:BAAANQADCgYIBgAAAA==.Slayn:BAAANQAECgcIEQAAAA==.Slyrak:BAAANQAECgUIBgAAAA==.',
Sm='Smitus:BAAANQABCgIIAgAAAA==.',
Sn='Snackie:BAAANQAECgUICwAAAA==.Snooty:BAAANQAECggJAgAAAA==.Snotpig:BAAANQAECggIBwAAAA==.',
So='Sokar:BAAANQAECggICAAAAA==.Sokolovva:BAAANQADCgcIDAAAAA==.Souled:BAAANQADCgUIBQABNQAECgkJMAAfAGQUAA==.Sourpunchkid:BAAANQAECgEIAQAAAA==.',
Sp='Spacedemon:BAAANQAECgUIDAAAAA==.Sparroh:BAAANQADCgYIBgAAAA==.Spikedriver:BAABNQAECoEXAAIGAAcKZA+lhADSAQAGAAcKZA+lhADSAQAAAA==.Spiky:BAAANQADCgMIAwAAAA==.',
St='Stariane:BAABNQAECoEZAAIDAAcKyxrbLAAPAgADAAcKyxrbLAAPAgAAAA==.Startaker:BAAANQADCggIDwAAAA==.Startaster:BAAANQADCgcIBwAAAA==.Starvoid:BAAANQAECgIIAgAAAA==.Steeldk:BAAANQAECgIJAgAAAA==.Stella:BAAANQAECgMIBAAAAA==.Stonyfist:BAAANQADCgEIAQAAAA==.Stonyy:BAAANQAECgIIAgAAAA==.Stubhorn:BAAANQADCgUICAAAAA==.',
Su='Summers:BAAANQADCgYICwAAAA==.Sumonmyface:BAABNQAECoEiAAMZAAgKoxeeIABiAQAZAAQKFh6eIABiAQAYAAUKyBKnrABIAQAAAA==.Superillbomb:BAAANQADCgYJCQAAAA==.Superold:BAAANQAECgUICgAAAA==.',
Sw='Swamprot:BAAANQAECgUIEAAAAA==.',
Sy='Syletage:BAAANQADCgYICwAAAA==.Syral:BAAANQADCgYICwAAAA==.Syrel:BAAANQAECgEIAwAAAA==.',
Ta='Tailfordays:BAAANQADCgIIAgAAAA==.Tanky:BAAANQADCgIIAgAAAA==.Tantor:BAAANQADCgEIAQAAAA==.Taylorswift:BAAANQAECgYIDwAAAA==.',
Tc='Tchiratha:BAAANQADCgIIAgABNQAECgcIHQANABYTAA==.',
Te='Tednougat:BAAANQADCgYIBgAAAA==.Telain:BAABNQAECoEaAAQKAAcKgQuamwAmAQAKAAYKZwmamwAmAQANAAUKQgxp7gAGAQAQAAIKSQySUwBjAAAAAA==.Tensuki:BAAANQADCgQIBAAAAA==.Tesh:BAAANQADCgQIBgAAAA==.',
Th='Thaelynn:BAAANQADCgYIEAAAAA==.Thakilla:BAABNQAECoEnAAIaAAgKaxOxNgAOAgAaAAgKaxOxNgAOAgAAAA==.Thordrik:BAAANQAECgEIAQAAAA==.Thorix:BAAANQAECgUICQAAAA==.Thornhub:BAAANQAECggICgABNQAFFAgIKwAZAI4iAA==.Thrustwood:BAAANQADCgMIAwAAAA==.',
Ti='Tiammanth:BAAANQAECgMIBAAAAA==.Tigerbrew:BAAANQADCgUIBQAAAA==.Tigerburn:BAAANQADCgQIBAAAAA==.Tikya:BAAANQADCgYIBwAAAA==.Tilsit:BAAANQAECggIDQAAAA==.Timberreaper:BAAANQADCgcICAAAAA==.Tinyz:BAAANQAECgIIBAAAAA==.',
To='Tonythetiger:BAAANQAECgQIBAABNQAECgkJKAAUAHwYAA==.',
Tr='Train:BAAANQADCgcIBwAAAA==.Trei:BAAANQADCgIIAgABNQAECgcIDQABAAAAAA==.Trexlot:BAAANQADCgIIAgAAAA==.Trinjal:BAAANQAECgEIAgAAAA==.',
Tu='Tubbylumpkin:BAAANQADCggIDAAAAA==.Tummi:BAAANQADCgcIEAAAAA==.Tumnus:BAAANQAECgEIAQAAAA==.',
Ty='Tyjan:BAAANQAECgIJAgAAAA==.',
['Tâ']='Tâfa:BAAANQADCggICAAAAA==.',
Uh='Uhtred:BAAANQADCgYIBwAAAA==.',
Ul='Ulti:BAAANQAECgUIEAAAAA==.',
Un='Unholyheart:BAAANQADCgEIAQAAAA==.',
Va='Varthios:BAAANQABCgQIBgAAAA==.Varyusha:BAAANQAECgEIAQAAAA==.',
Ve='Velantra:BAAANQAECggICQAAAA==.Venari:BAAANQAECgUICwAAAA==.',
Vi='Vilelyn:BAAANQAECgQICgABNQADCgEIAQABAAAAAA==.Viloria:BAAANQAECgUIEAAAAA==.Vincent:BAAANQADCgQIBAAAAA==.Virrard:BAABNQAECoEZAAIGAAcK9hvdXQAyAgAGAAcK9hvdXQAyAgAAAA==.',
Vl='Vladimor:BAAANQAECgMIBAAAAA==.Vladimyrr:BAAANQADCgUJCAAAAA==.',
Vo='Vozrezz:BAAANQAECgQIBwAAAA==.',
['Vë']='Vëda:BAABNQAECoEfAAILAAkKuhu0JAC8AgALAAkKuhu0JAC8AgAAAA==.',
Wa='Waffle:BAAANQAECgIIAwABNQAECgkJJgAhAIImAA==.Warage:BAAANQADCgYIBwAAAA==.Warske:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.',
Wh='Wheaties:BAAANQAECgQIBAABNQAECgkJKAAUAHwYAA==.Whizzie:BAABNQAECoEwAAIfAAkKZBRwhQBaAgAfAAkKZBRwhQBaAgAAAA==.Whizzlecrank:BAABNQAECoEpAAIfAAgK6xFhrQAGAgAfAAgK6xFhrQAGAgAAAA==.',
Wi='Wicker:BAABNQAECoEkAAMaAAgKAhpoOwDuAQAaAAYKzRtoOwDuAQAFAAMKmwnVTQClAAAAAA==.Willpharaoh:BAAANQADCgUICgAAAA==.Wiçker:BAAANQADCgIIAgABNQAECggIJAAaAAIaAA==.',
Wo='Wolford:BAAANQADCgYIBgAAAA==.',
Wr='Wras:BAAANQAECgMIBgAAAA==.Wrectt:BAAANQAECgUIDgAAAA==.',
['Wò']='Wòbbles:BAAANQAECgQICQAAAA==.',
Xa='Xandrah:BAAANQADCgUJBQAAAA==.Xandrel:BAABNQAECoEdAAINAAcKoQyxuwBsAQANAAcKoQyxuwBsAQAAAA==.',
Xe='Xed:BAABNQAECoEfAAIOAAcKbhmZSgAfAgAOAAcKbhmZSgAfAgAAAA==.Xenogears:BAABNQAECoEVAAIHAAgKqhgTGgBsAgAHAAgKqhgTGgBsAgAAAA==.',
Xi='Xiansai:BAABNQAECoEaAAIcAAcKyBCaKgCqAQAcAAcKyBCaKgCqAQAAAA==.',
Ya='Yappey:BAAANQAECgYIBgAAAA==.',
Yi='Yippee:BAAANQAECgQIBAAAAA==.',
Yo='Youthinasia:BAAANQAECgUICwAAAA==.',
Ze='Zerega:BAAANQADCgcIEwABNQAECgYILwAIANILAA==.',
Zh='Zhi:BAAANQAECgMIBQAAAA==.Zhukov:BAAANQADCgYIBgABNQADCggIDwABAAAAAA==.',
Zo='Zombiehippo:BAABNQAECoEeAAIfAAkKIRl6VADHAgAfAAkKIRl6VADHAgAAAA==.',
['Áu']='Áutarch:BAAANQAECgQICgAAAA==.',
['Ðe']='Ðemøn:BAAANQADCggIGAAAAA==.',
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
