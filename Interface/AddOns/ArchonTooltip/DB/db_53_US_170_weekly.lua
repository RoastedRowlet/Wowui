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

local lookup = {'Warlock-Affliction','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','Priest-Holy','Priest-Shadow','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Warrior-Fury','Rogue-Assassination','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Mage-Arcane','Unknown-Unknown','Druid-Feral','Mage-Frost','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Devourer','Druid-Guardian','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Evoker-Devastation','Rogue-Subtlety','DemonHunter-Havoc','Warrior-Protection','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation',}
local provider = {region='US',realm='Norgannon',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Absol:BAABNQAECn8sAAMBAAoKzyKkAACaAwABAAoKwCKkAACaAwACAAgKUB/3PQCZAgAAAA==.',
Ac='Achilles:BAABNQAECn8rAAMDAAoKtRKRmADyAQADAAoK9A+RmADyAQAEAAQKNxGpFwDNAAAAAA==.',
Ad='Adenox:BAAANQAECgMIAwAAAA==.',
Ae='Aeon:BAAANQAECgIIAwAAAA==.Aerís:BAAANQADCgIIAgAAAA==.',
Ah='Ahsokatano:BAABNQAECn8gAAMFAAgKhRntSQA7AgAFAAgKhRntSQA7AgAGAAEKAACaPgEuAAAAAA==.',
Ai='Ailing:BAAANQADCgYIDAAAAA==.Aimspet:BAAANQAECgQIEAAAAA==.Airocket:BAAANQADCgMIAwAAAA==.',
Ak='Akasha:BAAANQABCgMIBwAAAA==.Akos:BAAANQAECgYIBgABNQAECgoKTAAHALoXAA==.',
Al='Alzaeryan:BAABNQAECn8XAAIIAAgKQRRwQwDmAQAIAAgKQRRwQwDmAQAAAA==.',
Am='Am:BAAANQADCgYIBgAAAA==.Amonet:BAAANQADCgcIFwAAAA==.',
An='Anamis:BAABNQAECn8hAAMJAAkKpBSXUwAoAgAJAAkKpBSXUwAoAgAKAAEKHwXcgQAoAAAAAA==.Angras:BAABNQAECn8YAAMLAAYKogsPiQDbAAALAAUKwwwPiQDbAAAMAAUK0ga8mwDHAAAAAA==.',
Ap='Aphalock:BAABNQAECn8iAAINAAgKHgW6KQAuAQANAAgKHgW6KQAuAQAAAA==.',
Ar='Ariûs:BAABNQAECn8WAAIOAAYKuw1cCQDvAAAOAAYKuw1cCQDvAAAAAA==.Arlin:BAAANQADCgcIDgAAAA==.Arlorian:BAABNQAECn8vAAIPAAkKFQpqPwDQAQAPAAkKFQpqPwDQAQAAAA==.Arrenn:BAAANQAECgQICQAAAA==.Arrowsmites:BAABNQAECn8aAAIQAAgKoBc8XQBeAgAQAAgKoBc8XQBeAgAAAA==.',
As='Askelad:BAABNQAECn8YAAIDAAYKgwdWBgEUAQADAAYKgwdWBgEUAQAAAA==.',
Au='Aubani:BAABNQAECn8iAAMRAAgKag9rbQDPAQARAAgKag9rbQDPAQADAAYKmg8+6gBHAQAAAA==.',
Ax='Axelot:BAAANQADCgQIBAAAAA==.',
Ay='Ayperos:BAABNQAECn8wAAISAAkKzA03JgBsAQASAAkKzA03JgBsAQAAAA==.',
Ba='Bakedpally:BAABNQAECn8XAAIDAAcKhQdP9wAvAQADAAcKhQdP9wAvAQAAAA==.Bakedwarrior:BAAANQADCgIIAgAAAA==.Bandomar:BAAANQAECgIIAwAAAA==.Baniemo:BAAANQAECgQIBAAAAA==.Banigor:BAAANQAECgQICAAAAA==.Bankaltanon:BAAANQAECgQIBAAAAA==.Baragnis:BAAANQAECgUIBQAAAA==.',
Be='Beavur:BAAANQAECgUIEAAAAA==.Beck:BAABNQAECn8jAAIDAAgKziH5JwCHAQADAAgKziH5JwCHAQAAAA==.Beggars:BAAANQAECgQICAAAAA==.Bereth:BAAANQADCgcIFwAAAA==.Berreydingle:BAAANQADCggJFwAAAA==.',
Bi='Bigboii:BAAANQAECgEIAQAAAA==.Bigkitty:BAAANQAECgIIAgABNQAECggIHwATAAcWAA==.Bikinibrenda:BAAANQAECgQICgAAAA==.',
Bl='Blackhuuf:BAAANQADCgUIBQAAAA==.Blitzedbust:BAAANQADCggIFQAAAA==.Bloodmender:BAAANQADCgYIBwABNQAECgkJKQATAFEjAA==.Bluesummer:BAAANQAECgYICgABNQAECggIIAALAJwdAA==.',
Bo='Bobeh:BAAANQAECgEIAgABNQADCgEIAQAUAAAAAA==.Bolts:BAAANQABCgEIAQAAAA==.Bonzai:BAAANQAECgMIAgABNQAECgoKLAABAM8iAA==.Boomskittles:BAAANQABCgMIAwAAAA==.Borat:BAABNQAECn8kAAITAAkK+iPOCQCxAwATAAkK+iPOCQCxAwAAAA==.Borsam:BAAANQABCgcICQAAAA==.',
Br='Brendameeks:BAAANQADCgQIBAAAAA==.Broadzinatl:BAAANQAECgIIAgAAAA==.Brom:BAAANQAECgQIBgAAAA==.Brutesse:BAAANQAECgQIDAAAAA==.Bròly:BAAANQADCgMIAwAAAA==.',
Bu='Buttercups:BAAANQADCgQIBwAAAA==.',
['Bè']='Bètflèch:BAAANQAECgIIAgAAAA==.',
['Bø']='Bøss:BAAANQADCggIFQAAAA==.',
Ca='Cad:BAAANQADCgYIEAAAAA==.Calytrix:BAEBNQAECn8kAAMIAAkKchPxOgAcAgAIAAkKchPxOgAcAgAVAAEKXxG4QAA5AAAAAA==.Captnhammer:BAAANQADCgEIAQAAAA==.Carnelian:BAAANQADCgcIFAAAAA==.Castration:BAAANQADCgYICQAAAA==.',
Ce='Ceylan:BAABNQAECn8ZAAIWAAgKzRpjCABcAgAWAAgKzRpjCABcAgAAAA==.',
Ch='Charlz:BAAANQAECgcIBwAAAA==.Charsifood:BAAANQAECgcIDgAAAA==.Chat:BAABNQAECn8XAAIXAAgKaiYbAwCEAwAXAAgKaiYbAwCEAwAAAA==.Cheatpriest:BAABNQAECn8oAAIJAAkKKRM6aADmAQAJAAkKKRM6aADmAQAAAA==.Chepis:BAAANQADCgcJEAAAAA==.Chesthyr:BAAANQADCgcIDgAAAA==.Chestoe:BAAANQAECgUIEAAAAA==.Chitchatted:BAAANQADCgIIAgAAAA==.',
Ci='Cindrethresh:BAAANQADCgMIAwAAAA==.',
Co='Cognition:BAABNQAECn8xAAIQAAkK5yHIBwBKAgAQAAkK5yHIBwBKAgAAAA==.Coldvengance:BAABNQAECn8eAAIOAAkKpgdtEwBpAQAOAAkKpgdtEwBpAQAAAA==.',
Cr='Cranknstein:BAAANQADCggJCAABNQADCggIEQAUAAAAAA==.Crazh:BAAANQAECgIIAwAAAA==.Crazycalla:BAAANQAECgQIBQAAAA==.Croven:BAAANQADCgUIBQAAAA==.',
Cu='Cuensour:BAAANQADCgcJDQAAAA==.Cutemenace:BAAANQADCgIIAgABNQAECgkJHAAEAJ0gAA==.',
Cy='Cymindel:BAABNQAECn8oAAILAAkKcBbPOgAaAgALAAkKcBbPOgAaAgAAAA==.Cyphr:BAAANQAECgQICAAAAA==.',
Da='Dakotà:BAABNQAECn8dAAIQAAcKThMRSAAkAQAQAAcKThMRSAAkAQAAAA==.Darc:BAAANQAECgUICQAAAA==.Daredayo:BAAANQADCgIIAgAAAA==.Darkangelz:BAAANQAECgUIBQAAAA==.Darklorising:BAAANQAECgIIAgAAAA==.Darktroll:BAAANQADCgYICAAAAA==.',
De='Dejno:BAABNQAECn8WAAMOAAcKlSD7CQAxAgAOAAYKxCL7CQAxAgASAAIK/BTGKAGFAAAAAA==.Deleted:BAAANQADCgUIBQABNQAECgkJKQATAFEjAA==.Dethra:BAAANQAECgQIDgAAAA==.Dezign:BAACNQAFFH8eAAMWAAcKOyEuAQB7AQAWAAQKpSMuAQB7AQATAAYKxx6wCAAaAQA1AAQKf0IAAxYACgp8JlEAANwDABYACQoMJlEAANwDABMACgozJYgFAH0CAAAA.',
Do='Dolgorukov:BAABNQAECn8hAAIQAAgKhw3MkwDhAQAQAAgKhw3MkwDhAQAAAA==.Dologony:BAAANQAECgYIDAAAAA==.Dorgar:BAAANQADCgcIBwAAAA==.',
Dr='Draccosa:BAAANQADCgIIAgAAAA==.Dracigor:BAAANQABCgcIFAAAAA==.Dragonmage:BAAANQAECgUICwAAAA==.Drakhan:BAAANQAECgUIBgAAAA==.Drakma:BAAANQAECgMIBQAAAA==.Drastio:BAAANQADCgMIAwAAAA==.Drikken:BAABNQAECn8yAAMYAAkKfxeSCwAVAgAYAAkKfxeSCwAVAgAZAAgKERDiGADmAAAAAA==.Drmaker:BAAANQAECgMIBAAAAA==.Druj:BAEANQADCgcIBwABNQAECgkJJAAIAHITAA==.',
Du='Durasan:BAAANQADCgMIAwAAAA==.Duressa:BAAANQADCggICAAAAA==.',
['Dö']='Dötdötdead:BAAANQAECgYIDQAAAA==.',
Ef='Effindin:BAAANQADCgYIBgAAAA==.Effinsick:BAAANQAECgQIBAAAAA==.',
Ei='Eisheth:BAAANQAECgEIAQAAAA==.',
El='Elerav:BAAANQAECgQIBwAAAA==.Ellysiaa:BAAANQADCggIJwAAAA==.',
Em='Emmakyn:BAABNQAECn8aAAMIAAkKBQ9lQgDtAQAIAAkKdg5lQgDtAQAaAAEK3BamXAA8AAAAAA==.',
En='Endjinns:BAAANQADCggICAAAAA==.Enyxea:BAAANQAECgMIBAAAAA==.',
Er='Erodin:BAAANQADCgYICwAAAA==.',
Es='Esman:BAAANQADCgMIAwAAAA==.',
Ey='Eyedontknow:BAABNQAECn8WAAIEAAYKzhx/HAAIAgAEAAYKzhx/HAAIAgAAAA==.',
Ez='Ezzka:BAABNQAECn8tAAMMAAgKuiAwBAADAgAMAAgKlCAwBAADAgALAAIKxhsUqgB8AAAAAA==.',
Fa='Faceless:BAAANQAECgYIBQAAAA==.Failroots:BAAANQAECgIIAgAAAA==.False:BAAANQAECgIIAgAAAA==.Farnsworth:BAAANQAECgcIDAAAAA==.Farzix:BAAANQAECgYIEQAAAA==.Fatherdrew:BAAANQAECggIEgAAAA==.Façade:BAABNQAECn8hAAMbAAoKnxKNNwD4AQAbAAkKQBSNNwD4AQAMAAcKrw9TbQBeAQAAAA==.',
Fe='Fefifabrizio:BAAANQAECgEIAQAAAA==.Felix:BAAANQAECgUIDAAAAA==.Felraena:BAAANQADCgIIAgAAAA==.',
Fi='Finnagas:BAAANQAECgEJAQAAAA==.Finnw:BAAANQABCgcJCgAAAA==.Firelite:BAABNQAECn8YAAMGAAcKOQnXMgD1AAAGAAcKOQnXMgD1AAAFAAEKkwEyMgEeAAAAAA==.',
Fl='Flairadin:BAABNQAECn8iAAIRAAkKfxmsPQBuAgARAAkKfxmsPQBuAgAAAA==.Flee:BAAANQAECgQIBAABNQAECgUIBQAUAAAAAA==.Fleromars:BAAANQAECgUIBQAAAA==.Flexo:BAAANQAECgQIBQABNQAECgcIDAAUAAAAAA==.',
Fo='Fookmii:BAAANQADCgUIBgAAAA==.',
Fr='Frogfist:BAAANQAECgMIAwAAAA==.Frowdawn:BAABNQAECn8dAAIPAAcKkwrhFgARAQAPAAcKkwrhFgARAQAAAA==.',
Ga='Gallea:BAAANQAECgIIAgAAAA==.Garbanzo:BAAANQAECgUIBQAAAA==.Garythenpc:BAAANQADCgcIFwAAAA==.',
Ge='Genericeric:BAAANQAECgUIBwAAAA==.Getsumei:BAAANQAECgcICAAAAA==.',
Gi='Gidgett:BAAANQADCgcIFAAAAA==.Gilas:BAAANQADCgcIBwAAAA==.',
Gl='Glacialkitty:BAABNQAECn8fAAIHAAgKiwUYQAAlAQAHAAgKiwUYQAAlAQAAAA==.Glizzygoblin:BAAANQADCgQIBAAAAA==.',
Go='Gobibug:BAAANQADCgIJAgAAAA==.Googoobler:BAAANQAECgEIAQAAAA==.Goudalovin:BAAANQADCgQIBAABNQAECggIHwATAAcWAA==.Goudanight:BAAANQADCgIIAgABNQAECggIHwATAAcWAA==.Goudatime:BAAANQAECgUIEwABNQAECggIHwATAAcWAA==.',
Gr='Greenknight:BAAANQADCggICQAAAA==.Greenmagus:BAAANQAECgEJAQAAAA==.Grenadon:BAAANQADCgcIFgAAAA==.Greyni:BAAANQABCgEIAQAAAA==.',
Ha='Hadorya:BAAANQADCgQIBAAAAA==.Hakibalboa:BAABNQAECn8wAAIcAAkKrgsrEwCxAQAcAAkKrgsrEwCxAQAAAA==.Hakitua:BAAANQADCgYIBgAAAA==.Harick:BAAANQADCgQIBAAAAA==.Hazard:BAABNQAECn8iAAIOAAkKIQ2rDwCvAQAOAAkKIQ2rDwCvAQAAAA==.',
He='Heis:BAAANQADCgcIDgAAAA==.Hellboii:BAAANQAECgcIDgAAAA==.Heyitsrat:BAABNQAECn8dAAIDAAcKJwiH6ABKAQADAAcKJwiH6ABKAQAAAA==.',
Ho='Hollowtips:BAAANQADCggIEgAAAA==.Holo:BAABNQAECn8tAAMGAAoKoSOtBwDtAQAGAAkKxyOtBwDtAQAFAAkKHw8ldQCsAQAAAA==.Holyangus:BAAANQAECgUICgAAAA==.Housemom:BAAANQAECgYIDgAAAA==.',
Hu='Huntem:BAAANQADCgMIAgAAAA==.Huuginn:BAAANQADCggICgAAAA==.',
Ib='Ibbert:BAAANQADCggIGQAAAA==.',
Ic='Icculus:BAAANQAECgIIAwAAAA==.',
Il='Illadai:BAAANQADCggICAAAAA==.',
Im='Imamunch:BAAANQADCgIIAgAAAA==.Imaresmashy:BAAANQADCgIIAgABNQAECgQIBQAUAAAAAA==.Iminyou:BAABNQAECn8jAAIGAAgKJhWTYAAAAgAGAAgKJhWTYAAAAgAAAA==.',
Io='Iolz:BAAANQABCgQIBgABNQAECgoKKQASAD4WAA==.',
Ja='Jaenei:BAAANQAECgMIBAAAAA==.Janet:BAAANQADCgYIBgABNQAECgkJLgAJAIgkAA==.',
Je='Jeeb:BAABNQAECn8tAAITAAcKUxAsRQAyAQATAAcKUxAsRQAyAQAAAA==.',
Ji='Jinxta:BAABNQAECn8hAAINAAkKgRsGBQDQAgANAAkKgRsGBQDQAgAAAA==.',
Jo='Joansnow:BAAANQAECgcIDQAAAA==.Joeeo:BAABNQAECn8vAAMJAAoK5xt5KgC/AgAJAAoK5xt5KgC/AgAKAAcKigjlPgA2AQAAAA==.',
Ju='July:BAAANQAECgMIBAAAAA==.Julytonidas:BAABNQAECn8cAAITAAkKLxZxmgBMAgATAAkKLxZxmgBMAgAAAA==.Jurac:BAAANQADCggIFQAAAA==.',
Ka='Kaimargonar:BAABNQAECn8VAAINAAYKVxBHIgBfAQANAAYKVxBHIgBfAQAAAA==.Kaitoi:BAAANQAECgUIEwAAAA==.Kamakizeg:BAABNQAECn8cAAIDAAcKVQ6FXgAIAQADAAcKVQ6FXgAIAQAAAA==.Kamayla:BAAANQADCgYIBgAAAA==.Kateria:BAAANQAECgMIAwABNQAECggILQAMALogAA==.Katimalice:BAAANQADCgQJDQAAAA==.',
Ke='Keathry:BAAANQADCgcICwAAAA==.Keyzeus:BAAANQAECgIIAwAAAA==.',
Kh='Khas:BAAANQADCgMIAwAAAA==.Khui:BAACNQAFFH8MAAIXAAUKeyQNBAClAQAXAAUKeyQNBAClAQA1AAQKfysAAxcACgoyIrIEAFoDABcACgoyIrIEAFoDAB0ABQqUHQk1AG0BAAAA.',
Ki='Killatu:BAAANQABCggIDQAAAA==.Killerdeath:BAAANQAECgMIAwAAAA==.',
Kn='Knìghtmàrè:BAACNQAFFH8MAAMMAAYKiQ8OAwDtAAAMAAUKJw4OAwDtAAALAAMKhRRxHwCPAAA1AAQKfysAAwwACgqzIxYUABgDAAwACgqzIxYUABgDAAsABwpzHuw0ADgCAAAA.',
Ko='Koltharaz:BAACNQAFFH8GAAIeAAIK4h8TCgDAAAAeAAIK4h8TCgDAAAA1AAQKfysAAh4ACgrHG6cJANYCAB4ACgrHG6cJANYCAAAA.Korloff:BAAANQADCggIEwABNQAECgIIAwAUAAAAAQ==.Kozan:BAAANQAECgIIAwAAAQ==.',
Kr='Krazsz:BAAANQADCgQIBAAAAA==.Krazykraw:BAAANQAECgIIAgAAAA==.Krazylock:BAAANQAECgQICAAAAA==.',
Ku='Kuiy:BAAANQADCgIIAgAAAA==.Kumah:BAAANQABCgEIAQAAAA==.Kungfuupanda:BAAANQAECgcIEwAAAA==.',
Ky='Kylar:BAAANQAECgQIBgAAAA==.',
La='Lateralus:BAABNQAECn8eAAIMAAgKsSIsMABvAgAMAAgKsSIsMABvAgAAAA==.Latt:BAAANQAECgUICgABNQAECggIHgAMALEiAA==.Lawluss:BAABNQAECn8YAAIQAAcKcxQ5vgCHAQAQAAcKcxQ5vgCHAQAAAA==.Layonface:BAAANQAECgQICAAAAA==.',
Le='Legacyshot:BAAANQAECgQIBQAAAQ==.Lelwani:BAAANQADCgEIAQAAAA==.',
Li='Lickthecrit:BAAANQAECgMIBQAAAA==.Lightguard:BAAANQADCggICQAAAA==.Lighthouse:BAABNQAECn8rAAMRAAkK8xbZSgA9AgARAAkK8xbZSgA9AgADAAMK+QZqXgGJAAAAAA==.Lightload:BAAANQAECgQICAAAAA==.Lileth:BAAANQAECgIIAwAAAA==.',
Lo='Lolhahabaha:BAAANQAECgUICQAAAA==.Lonê:BAAANQAECgIIAgAAAA==.Loopie:BAAANQAECgEIAQAAAA==.Lorax:BAAANQAECgYICAAAAA==.',
Lu='Luckÿ:BAAANQAECgEJAQAAAA==.Luminah:BAAANQABCgIIAQAAAA==.',
Ly='Lypally:BAABNQAECn8qAAIDAAkKBgWv9QAyAQADAAkKBgWv9QAyAQAAAA==.',
['Lï']='Lïllïth:BAABNQAECn8bAAIQAAcKdQZywQB/AQAQAAcKdQZywQB/AQAAAA==.Lïly:BAAANQAECgUIBwABNQAECgQIBQAUAAAAAA==.',
['Ló']='Lóla:BAABNQAECn8kAAIZAAgKvB4dEwDRAgAZAAgKvB4dEwDRAgAAAA==.',
Ma='Madeah:BAACNQAFFH8dAAIPAAcKtBSuAACqAQAPAAcKtBSuAACqAQA1AAQKfxYAAw8ACQpBE68XAAsBAB8ACApcCrMpAHcBAA8AAwp8Ha8XAAsBAAAA.Madforge:BAABNQAECn8uAAIFAAgKzxmBGgCIAQAFAAgKzxmBGgCIAQAAAA==.Magegrizz:BAAANQAECgYIDgAAAA==.Magnyson:BAAANQAECggICAAAAA==.Mahimahi:BAAANQADCgYICgAAAA==.Manahole:BAABNQAECn8yAAITAAoKmx4pAwDMAgATAAoKmx4pAwDMAgAAAA==.Mariacuras:BAABNQAECn8XAAIRAAgKHA0phwCGAQARAAgKHA0phwCGAQAAAA==.Marijwana:BAAANQAECgYIEAAAAA==.Martis:BAABNQAECn8lAAIbAAkKxwiRSQCVAQAbAAkKxwiRSQCVAQAAAA==.Marynne:BAABNQAECn8kAAIHAAcKiAvXEwAlAQAHAAcKiAvXEwAlAQAAAA==.Mazuko:BAABNQAECn8fAAIgAAkK0BX1LwAoAgAgAAkK0BX1LwAoAgAAAA==.',
Mc='Mctank:BAAANQADCggICgAAAA==.',
Me='Mecandry:BAABNQAECn8vAAIQAAgKWBX9ZQBIAgAQAAgKWBX9ZQBIAgAAAA==.Mecks:BAAANQADCgcIGAAAAA==.Meepe:BAAANQADCgcIDQAAAA==.Melivant:BAABNQAECn8YAAQEAAcKbBITMwBKAQAEAAYKbBITMwBKAQADAAQKUQvbNAHLAAARAAEKXgKhNQEiAAAAAA==.Meranda:BAABNQAECn8fAAITAAgKBxaHqAAxAgATAAgKBxaHqAAxAgAAAA==.Merriklade:BAABNQAECn8iAAQOAAgKqQ3GEgB1AQAOAAcK4A7GEgB1AQASAAcK7wWL1QBFAQAhAAEKpQd3JQArAAAAAA==.Merrikoid:BAAANQAECgYIEwAAAA==.Merrikwolf:BAAANQADCggIDgAAAA==.',
Mi='Mico:BAAANQAECgUIDAAAAA==.Missyjelliot:BAAANQADCgEIAQAAAA==.',
Mo='Morbidstyle:BAAANQAECgQIBQABNQAECgoKLwAGAFMUAA==.Morgoth:BAABNQAECn8qAAICAAkKTxdsUwBbAgACAAkKTxdsUwBbAgAAAA==.Morthos:BAAANQADCgcICgAAAA==.Mosry:BAABNQAECn8qAAILAAgKZx8jHADNAgALAAgKZx8jHADNAgABNQABCgQIBgAUAAAAAA==.Mourneblood:BAAANQADCgUIBQAAAA==.',
My='Myora:BAEANQADCgIIAgABNQAECgkJJAAIAHITAA==.Mythundirus:BAABNQAECn8VAAIZAAcK+wHcUQDUAAAZAAcK+wHcUQDUAAAAAA==.',
['Mà']='Màrli:BAABNQAECn8mAAILAAgK/hgmGAApAQALAAgK/hgmGAApAQAAAA==.',
['Mâ']='Mâgs:BAABNQAECn8eAAIEAAgKRA2MLgBpAQAEAAgKRA2MLgBpAQAAAA==.',
Na='Nakasid:BAABNQAECn8tAAMJAAoKexYGCgBEAgAJAAoKexYGCgBEAgAKAAUKBgcBUADSAAAAAA==.Nashoba:BAAANQADCgYJCwAAAA==.Natooka:BAAANQADCgUIBQAAAA==.',
Ne='Nein:BAAANQAECgQIDAAAAA==.Neins:BAAANQADCgYIEAABNQAECgQIDAAUAAAAAA==.Nevaehstar:BAABNQAECn8xAAITAAoK5QxvxQD5AQATAAoK5QxvxQD5AQAAAA==.',
Ni='Nibuto:BAAANQAECgUICgAAAA==.Nijun:BAEBNQAECn8kAAIJAAkK8QveewCmAQAJAAkK8QveewCmAQAAAA==.Nik:BAAANQAECgYICgAAAA==.Nikolia:BAAANQAECgQIDwAAAA==.Ninetynine:BAAANQADCgQIBAAAAA==.Nini:BAABNQAECn8VAAIIAAcKEAJDPABsAAAIAAcKEAJDPABsAAAAAA==.Ninx:BAAANQADCgUICQAAAA==.',
No='Noivana:BAAANQABCgEIAQABNQAFFAUIEAAgALMbAA==.',
Ny='Nystel:BAAANQADCgEIAQAAAA==.',
Ol='Ollichi:BAAANQADCgIIAgAAAA==.',
Or='Ornn:BAAANQAECgcICwABNQAECgoKLAABAM8iAA==.',
Os='Osoroshi:BAAANQADCgYJBgABNQAECggILwAQAFgVAA==.',
Ov='Overtime:BAAANQADCggIEQAAAA==.',
Pa='Padmê:BAAANQADCgMIAwAAAA==.Paladrak:BAAANQADCgIIAgAAAA==.Pandamared:BAAANQADCggICgAAAA==.Patronous:BAAANQADCgYIDAAAAA==.',
Ph='Phenol:BAAANQADCgEIAQAAAA==.',
Po='Polog:BAAANQAECgIIAgABNQAECgkJKQATAFEjAA==.Porkchoplust:BAAANQADCgUIBQAAAA==.Porkribs:BAABNQAECn8bAAIRAAgKkRqKRQBQAgARAAgKkRqKRQBQAgAAAA==.',
Pr='Premalone:BAAANQADCgUIBQAAAA==.',
Pu='Puca:BAAANQADCgcIFwAAAA==.Pumdmuc:BAAANQAECgUIDwABNQAECgkJKAAFAC0gAA==.Punchymcheal:BAAANQAECgIIBAABNQAECgoKNAAJAIkaAA==.',
Qu='Quikglaives:BAAANQAECgEIAQAAAA==.Quille:BAABNQAECn8hAAIQAAgK2iC4MwBWAQAQAAgK2iC4MwBWAQAAAA==.',
Ra='Ragretts:BAAANQAECgEIAQAAAA==.Rahhem:BAAANQADCgYIBgAAAA==.Ranmo:BAAANQAECgcIDwAAAA==.Ratkol:BAAANQABCgIIAgAAAA==.Raysdknight:BAAANQADCgIJBwAAAA==.',
Re='Recbra:BAAANQABCgUIBQAAAA==.Redrek:BAAANQADCgcIKAAAAA==.Redshunter:BAAANQADCgcIEwAAAA==.Redsmonk:BAAANQADCgYIBgAAAA==.Redwinter:BAABNQAECn8gAAMLAAgKnB2NLABlAgALAAgKnB2NLABlAgAbAAEKAACVdwAAAAAAAA==.Reikisong:BAAANQAECgMIBAAAAA==.Reiluune:BAAANQADCgQIAwABNQAECggIJAAZALweAA==.Remmie:BAAANQADCgUIBwAAAA==.',
Rh='Rhagurion:BAABNQAECn82AAIaAAoKXia6AADtAwAaAAoKXia6AADtAwAAAA==.',
Ri='Riqua:BAAANQAECgMIBQAAAA==.',
Ro='Rockmonsta:BAAANQADCgYJCgAAAA==.Rockys:BAAANQABCgQIBQAAAA==.Roxies:BAAANQAECgMIBgAAAA==.',
Rp='Rpg:BAABNQAECn8bAAITAAkKjxkjmQBOAgATAAkKjxkjmQBOAgAAAA==.',
Ru='Runes:BAAANQAECgUIBgAAAA==.',
Sa='Saeti:BAABNQAECn83AAUVAAoK3yJuBQAnAwAVAAkK3yJuBQAnAwAHAAQK4AyeTwDLAAAIAAMK2xzOKgC3AAAaAAEKxB+XUwBWAAAAAA==.Sanare:BAAANQADCggICAABNQAECgoKNAAJAIkaAA==.Sanbit:BAAANQADCggIHAAAAA==.Santhaenis:BAAANQADCgcICQAAAA==.Sapplesauce:BAAANQADCggICQAAAA==.',
Se='Seethrowwar:BAABNQAECn8iAAMSAAkKuh6vOwDYAgASAAkKaB6vOwDYAgAhAAYKQRbiGwB9AQAAAA==.Senbit:BAAANQAECgUIDQAAAA==.Serenìty:BAAANQAECgUIDAAAAA==.Seresin:BAABNQAECn9MAAMHAAoKuhfJCgCMAQAHAAoKuhfJCgCMAQAIAAUKkwVbggDHAAAAAA==.',
Sh='Shadý:BAABNQAECn8dAAIQAAcKogQu5AA4AQAQAAcKogQu5AA4AQAAAA==.Shamanoodles:BAAANQADCggIFAABNQAECgkJKQATAFEjAA==.Shortwarrior:BAABNQAECn8YAAIOAAcKdhGzBgAxAQAOAAcKdhGzBgAxAQAAAA==.',
Si='Sianu:BAAANQAECgIIAwABNQAECgcIJAAHAIgLAA==.Sidraya:BAAANQAECgUIDAAAAA==.Silent:BAABNQAECn8pAAISAAoKPhbLPQApAQASAAoKPhbLPQApAQAAAA==.Silverserqet:BAAANQAECgUIEwAAAA==.',
Sl='Slipknaught:BAAANQABCgQIBQABNQAECgcIDQAUAAAAAA==.',
Sm='Smileyriley:BAAANQADCgUIBQAAAA==.',
Sn='Sneakylinks:BAAANQADCgIIAgABNQAECgkJGwATAI8ZAA==.',
So='Sonbit:BAAANQADCggJDwAAAA==.Sooki:BAAANQAECgMIBQAAAA==.Sophie:BAAANQAECgQIDgAAAA==.Soulber:BAAANQAECgMIBAAAAA==.',
Ss='Ssonbit:BAAANQADCggIEAAAAA==.',
St='Stefeana:BAAANQADCgYIBgAAAA==.Sternhoof:BAAANQABCgMIBQAAAA==.Stigma:BAAANQADCggIFQABNQAECggIEgAUAAAAAA==.Stylos:BAABNQAECn8jAAIiAAkK4Q7uBgCHAQAiAAkK4Q7uBgCHAQAAAA==.',
Su='Summersong:BAAANQADCgQIBAAAAA==.Sumofwhy:BAAANQADCgcIBwAAAA==.',
Sw='Swarli:BAAANQADCggIDQAAAA==.Swowtitbang:BAAANQAECgQICQAAAA==.',
Sy='Sylven:BAAANQAECgQIBQABNQAECgkJJgACAB4aAA==.',
Te='Tegbolt:BAABNQAECn8dAAMGAAgKeRXAZgDsAQAGAAgKghPAZgDsAQAiAAcKLhLWGwCmAQAAAA==.Teghorn:BAAANQAECggICAABNQAECggIHQAGAHkVAA==.Tekko:BAABNQAECn8yAAMaAAoK+xhYDQCRAgAaAAkKzhtYDQCRAgAVAAEKOQX8UAAQAAAAAA==.Tempestrike:BAABNQAECn8fAAIZAAoK+xk/BQDAAQAZAAoK+xk/BQDAAQAAAA==.',
Th='Theholymatt:BAABNQAECn8sAAMRAAoKZSNEEgA9AwARAAoKZSNEEgA9AwADAAEK7wSG+gA1AAAAAA==.Thendari:BAABNQAECn8/AAINAAkKjgs3EwDYAQANAAkKjgs3EwDYAQAAAA==.Theodus:BAABNQAECn8oAAITAAoK+RGQYAD8AAATAAoK+RGQYAD8AAAAAA==.Therayen:BAAANQADCgYJCwAAAA==.Thomeriddle:BAAANQABCgMIAQAAAA==.',
Ti='Tiferis:BAACNQAFFH8GAAIRAAMKkBMMDQCWAAARAAMKkBMMDQCWAAA1AAQKfywAAhEACgpzHf4eAPUCABEACgpzHf4eAPUCAAAA.Tigerclawss:BAAANQADCggIHgAAAA==.Tislam:BAAANQAECgMIBAAAAA==.',
To='Tobiquer:BAABNQAECn8xAAIJAAkKpCGBBgCJAgAJAAkKpCGBBgCJAgAAAA==.Torolf:BAAANQAECgMIAwAAAA==.',
Tq='Tqco:BAAANQADCgMIAwABNQAECgoKMgAaAPsYAA==.',
Tr='Traydra:BAAANQADCgUIBwAAAA==.Trinbug:BAAANQADCgEIAQAAAA==.Troglodyte:BAABNQAECn87AAIGAAoKmyDpAQDJAgAGAAoKmyDpAQDJAgAAAA==.',
Ts='Tsonokwabain:BAABNQAECn8VAAIbAAgKqBrpKgBFAgAbAAgKqBrpKgBFAgAAAA==.Tsunami:BAAANQADCgMIAwAAAA==.',
Tw='Twistdog:BAAANQABCgQIBgAAAA==.',
Ty='Tye:BAABNQAECn8WAAIQAAkKLRSkUwB2AgAQAAkKLRSkUwB2AgAAAA==.Tyranastrasz:BAABNQAECn8lAAQeAAkKzAVVHgBtAQAeAAgK1QVVHgBtAQAjAAQKjQLJIQA6AAAkAAEKTQCNKQANAAAAAA==.Tyye:BAABNQAECn8cAAIOAAcKiCJlCABhAgAOAAcKiCJlCABhAgAAAA==.',
['Tâ']='Tâjik:BAABNQAECn8jAAIfAAoKtATgKwCvAAAfAAoKtATgKwCvAAAAAA==.',
Ul='Ulquiorra:BAACNQAFFH8KAAMZAAQKog5sDQDUAAAZAAMKog5sDQDUAAAYAAIKQAiPBwBCAAA1AAQKfy8AAxkACgr6HA0QAPICABkACQr6HA0QAPICABgABAoIDe8gAL0AAAAA.',
Ut='Uthers:BAAANQADCgYIAgAAAA==.',
Va='Vaethund:BAAANQAECgMIBAAAAA==.Valgavoth:BAABNQAECn8VAAILAAkK4Bf/NwApAgALAAkK4Bf/NwApAgAAAA==.Vangar:BAAANQADCgQIBAAAAA==.Vanthion:BAAANQADCggICgAAAA==.',
Ve='Velara:BAAANQAECgQIBQAAAA==.Velinna:BAAANQADCgUIBwABNQAECgEIAQAUAAAAAA==.Venekor:BAAANQADCgIIAgAAAA==.',
Vi='Viriex:BAAANQADCgIIAgAAAA==.Vitoria:BAAANQAECgQIBgAAAA==.',
Vo='Voidlighter:BAABNQAECn80AAIJAAoKiRo1JADcAgAJAAoKiRo1JADcAgAAAA==.Volundr:BAABNQAECn8hAAIhAAkKhRYeDgBNAgAhAAkKhRYeDgBNAgAAAA==.Vonvaughan:BAAANQAECgIIAgABNQAECgIIAgAUAAAAAA==.',
Vy='Vynel:BAAANQADCgMIAwABNQAECgkJJgACAB4aAA==.Vynirion:BAAANQAECgEIAQAAAA==.',
Wa='Wardellmo:BAAANQADCgQIBAAAAA==.Wargtar:BAABNQAECn8bAAIPAAcKCBnbMwAMAgAPAAcKCBnbMwAMAgAAAA==.',
We='Weabe:BAAANQAECgIIAwAAAA==.',
Wh='Whiterrina:BAAANQADCgIJAgAAAA==.Whitespring:BAAANQAECgQICgABNQAECggIIAALAJwdAA==.',
Wo='Wolfgarou:BAAANQABCgIIAgAAAA==.',
Wy='Wyrdo:BAAANQADCgYIBgAAAA==.',
['Wù']='Wùsthof:BAABNQAECn8fAAIQAAkKYApKiQD4AQAQAAkKYApKiQD4AQAAAA==.',
Xa='Xandrios:BAAANQAECgEJAQAAAA==.',
Xi='Xiae:BAABNQAECn8iAAMGAAkK8RXzTABDAgAGAAgK6RbzTABDAgAFAAEKNRnXhQBMAAAAAA==.',
Ya='Yasuke:BAAANQADCgUJBQAAAA==.',
Ye='Yet:BAAANQAECgEIAQABNQAECgkJJAATAPojAA==.',
Yi='Yiffweaver:BAAANQAECgEIAQAAAA==.',
Yo='Yokochan:BAAANQABCgIIAgAAAA==.Yokoriazen:BAABNQAECn8vAAIDAAoKIBUMYQB2AgADAAoKIBUMYQB2AgAAAA==.',
Za='Zakaradin:BAAANQADCgcICAABNQAECgIIAwAUAAAAAA==.Zandigor:BAAANQAECgEIAQAAAA==.Zaraeliana:BAAANQAECgMIBAAAAA==.Zarastraza:BAABNQAECn8hAAMjAAcKtRJxIgC3AQAjAAcKtRJxIgC3AQAeAAUKFQt0JQAPAQAAAA==.',
Ze='Zephnor:BAABNQAECn8bAAMaAAcKahBlJABzAQAaAAYKxBJlJABzAQAIAAcKHgnTYgBDAQAAAA==.',
Zh='Zhao:BAAANQADCgYIBgAAAA==.',
Zm='Zmona:BAAANQAECgQIBAAAAA==.',
Zo='Zorsche:BAAANQAECgEIAQAAAA==.',
Zu='Zulrok:BAABNQAECn8hAAISAAgKqhDdoADLAQASAAgKqhDdoADLAQAAAA==.',
['Áb']='Ábsurd:BAAANQAECgYICAABNQABCgIIAQAUAAAAAA==.',
['Ðr']='Ðre:BAAANQAECgMIAwAAAA==.',
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
