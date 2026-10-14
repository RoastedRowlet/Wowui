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

local lookup = {'Mage-Arcane','Paladin-Retribution','Druid-Feral','Druid-Restoration','Unknown-Unknown','Druid-Balance','Rogue-Assassination','Shaman-Enhancement','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Windwalker','Paladin-Protection','Warrior-Fury','Shaman-Elemental','Warrior-Arms','DemonHunter-Devourer','Shaman-Restoration','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Priest-Holy','Druid-Guardian','DeathKnight-Unholy','Mage-Frost','Priest-Discipline','Hunter-Marksmanship','DeathKnight-Frost','Paladin-Holy','Monk-Brewmaster','Monk-Mistweaver','Warrior-Protection','DeathKnight-Blood','Warlock-Affliction','Rogue-Subtlety','Rogue-Outlaw','Priest-Shadow',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abrakådabruh:BAABNQAECn8gAAIBAAcKKhKTyADyAQABAAcKKhKTyADyAQAAAA==.Absolverator:BAAANQADCgQIBAAAAA==.Abzero:BAAANQAECgIIBAAAAA==.',
Ac='Acnologia:BAAANQAECgQIBAAAAA==.',
Ae='Aeropos:BAAANQABCgEIAQAAAA==.',
Ah='Ahron:BAABNQAECn8ZAAICAAgK9RWoegAyAgACAAgK9RWoegAyAgAAAA==.',
Ai='Ainjel:BAAANQAECgEIAQAAAA==.Ainz:BAAANQADCgYICgAAAA==.',
Ak='Akaitsuki:BAABNQAECn8iAAMDAAgKUhQVDwAeAgADAAgKUhQVDwAeAgAEAAQKzAGjYgB1AAAAAA==.',
Al='Alex:BAAANQADCggICAAAAA==.Alexdh:BAAANQADCgcIBwAAAA==.Alexr:BAAANQADCgUIBQABNQADCgcIBwAFAAAAAA==.Alexxh:BAAANQADCgMIAwABNQADCgcIBwAFAAAAAA==.Alisson:BAAANQADCgEIAQABNQADCgcIBwAFAAAAAA==.',
Am='Amarantus:BAAANQAECgcIBwABNQAECgkJMgAGAOkZAA==.Ammerie:BAAANQADCgUJBQAAAA==.Ampkhwa:BAAANQADCggIBwAAAA==.',
An='Anmoa:BAABNQAECn8WAAIHAAgKphnhHwB+AgAHAAgKphnhHwB+AgABNQAFFAUIDgAIAC4cAA==.Anmodru:BAAANQADCgUIBQABNQAFFAUIDgAIAC4cAA==.',
Ao='Aoefarm:BAAANQADCggIGAAAAA==.',
Aq='Aqulath:BAABNQAECn8iAAIJAAkK0SDvAwATAwAJAAkK0SDvAwATAwAAAA==.',
Ar='Aragos:BAAANQADCgEIAQAAAA==.Arcanizzon:BAAANQADCggICAAAAA==.Ardênt:BAAANQADCgIIAgAAAA==.Aridhol:BAAANQAECgUICQAAAA==.Arradrius:BAAANQAECggIEgAAAA==.',
As='Ashaala:BAAANQABCgIIBgAAAA==.Astravelle:BAAANQAECgQIBwAAAA==.',
At='Athená:BAAANQAECgUICQAAAA==.Athenä:BAABNQAECn8gAAIKAAkKXxl1HACyAgAKAAkKXxl1HACyAgAAAA==.',
Au='Aubrii:BAAANQAECgMIBAAAAA==.Aukatsang:BAABNQAECn8cAAILAAgK8x7MEgDBAgALAAgK8x7MEgDBAgAAAA==.',
Ay='Ayo:BAAANQADCgcIBwAAAA==.',
Az='Azeloth:BAAANQAECgYIEAAAAA==.',
Ba='Babzx:BAAANQADCgcICgAAAA==.Baladeva:BAABNQAECn8cAAIMAAcKOyLkDgCsAgAMAAcKOyLkDgCsAgAAAA==.Balekin:BAAANQAECgYICAAAAA==.Banaritaz:BAABNQAECn8XAAIBAAcKwxqUsgAcAgABAAcKwxqUsgAcAgAAAA==.Barbaricboss:BAAANQAFFAEIAQAAAA==.Barrak:BAAANQAECggIEgABNQAECggIGQACAPUVAA==.Bau:BAAANQADCgYICgAAAA==.',
Be='Bearomir:BAABNQAECn8fAAINAAgK3R+WBQDDAgANAAgK3R+WBQDDAgAAAA==.Beersnob:BAABNQAECn8dAAILAAgKkwuvMgB7AQALAAgKkwuvMgB7AQAAAA==.',
Bh='Bhis:BAAANQADCgMIBgAAAA==.',
Bi='Bigblcktotem:BAACNQAFFH8VAAIOAAUKYhYFDQCaAQAOAAUKYhYFDQCaAQA1AAQKfyQAAg4ACQr8IrQQAGYDAA4ACQr8IrQQAGYDAAAA.Bigmikeyg:BAABNQAECn8eAAICAAcKdApb0AB1AQACAAcKdApb0AB1AQAAAA==.Bigsteve:BAABNQAECn8bAAMPAAcKQhkNfwAaAgAPAAcKxxgNfwAaAgANAAEK1hu7KwBTAAAAAA==.',
Bl='Bloodhunter:BAAANQADCgUIBwAAAA==.',
Bo='Boomchickun:BAAANQABCgIIAgABNQAFFAUICQAQAPQNAA==.',
Br='Brandie:BAAANQADCgUIBgAAAA==.Brickley:BAAANQADCgYIBgABNQAECgkJIgAJANEgAA==.Bronzesun:BAAANQADCggICAAAAA==.',
Bu='Bubbahowl:BAAANQADCgUIBQAAAA==.',
['Bè']='Bèyork:BAABNQAECn8bAAIRAAgKQxQsXwDuAQARAAgKQxQsXwDuAQAAAA==.',
['Bø']='Bønd:BAAANQAECgIIAwAAAA==.',
Ca='Caicos:BAECNQAFFH8FAAISAAMK+wHyCgCfAAASAAMK+wHyCgCfAAA1AAQKfzIABBIACQpqEPARADECABIACQpqEPARADECABMAAwotCn9AAJcAABQAAQpXAYwoABkAAAAA.Calizon:BAAANQAECgcIEAAAAA==.Camc:BAAANQADCgQIBwAAAA==.Canowhoopass:BAABNQAECn8ZAAIOAAcKlATrsgAoAQAOAAcKlATrsgAoAQAAAA==.Caser:BAAANQADCgMJAwAAAA==.Caseynovak:BAAANQADCgUIBQAAAA==.Catharsis:BAAANQAECgIIAgAAAA==.',
Ce='Celenus:BAAANQAECggIDwAAAA==.Cell:BAACNQAFFH8QAAIPAAYKLQ5XDgDIAQAPAAYKLQ5XDgDIAQA1AAQKfzQAAg8ACQppI5oNAIwDAA8ACQppI5oNAIwDAAAA.Cellyne:BAAANQADCgUIBgAAAA==.Cerassin:BAACNQAFFH8JAAIQAAUK9A3bCABiAQAQAAUK9A3bCABiAQA1AAQKfywAAhAACQpRHXcRAN8CABAACQpRHXcRAN8CAAAA.Cereas:BAABNQAECn8cAAIKAAkKSBMdLAA9AgAKAAkKSBMdLAA9AgAAAA==.',
Ch='Cheesedawg:BAAANQADCgEIAQAAAA==.Cherrish:BAAANQADCgUICQAAAA==.Chicoh:BAAANQABCgYIBgAAAA==.Choofz:BAAANQADCggIEAAAAA==.',
Cl='Clariel:BAAANQAECgEIAQAAAA==.Cloud:BAABNQAECn8iAAIPAAkKNBdmTgCbAgAPAAkKNBdmTgCbAgAAAA==.Clukdogg:BAAANQAECgcIEgAAAA==.',
Co='Combination:BAACNQAFFH8SAAMVAAYK+w5pBADSAAAWAAUKyRFIEQB6AQAVAAMKJAhpBADSAAA1AAQKfzYAAxUACQo9IfMFALECABYACAqmITMmAOkCABUACQq+F/MFALECAAAA.Corva:BAAANQAECgIIAgABNQAECgUIDwAFAAAAAA==.Corvenall:BAABNQAECn8iAAISAAgKKBA0FgDmAQASAAgKKBA0FgDmAQAAAA==.',
Cr='Crashpad:BAAANQAECgUIBwAAAA==.Crossbow:BAABNQAECn8qAAIXAAkKwhm1PwCpAgAXAAkKwhm1PwCpAgAAAA==.',
Da='Daggers:BAAANQAECgUIBQAAAA==.Dakkan:BAAANQADCggIDAAAAA==.Dallarth:BAAANQADCgUIBQAAAA==.Danidani:BAABNQAECn8hAAIYAAgKjiFmIQDnAgAYAAgKjiFmIQDnAgAAAA==.Darkluster:BAAANQADCgQIBAAAAA==.Darrknes:BAAANQAECgEIAQAAAA==.Darshun:BAAANQADCgUICgAAAA==.Davinah:BAAANQAECgUICwAAAA==.Dayje:BAAANQADCgUICAAAAA==.',
De='Deathation:BAAANQAECgEIAQABNQAECgUIDwAFAAAAAA==.Deathbcmesyu:BAAANQAECgUIDQAAAA==.Deathhb:BAAANQAECggICQAAAA==.Demonovest:BAAANQAECgYIEQAAAA==.Demontoarch:BAAANQADCggICAAAAA==.',
Di='Diehappy:BAAANQAECgEIAQAAAA==.Dishonor:BAAANQADCgQICwAAAA==.',
Do='Dommage:BAAANQAECggIEwABNQAFFAUIDgAZAOYfAA==.Donkyote:BAAANQADCgEIAQAAAA==.Downbadd:BAAANQABCgQIBQAAAA==.',
Dr='Druida:BAABNQAECn8XAAQEAAgKmwphPgArAQAEAAYKEQxhPgArAQAGAAQKAwX5kQCJAAAZAAEKAABjXQA1AAAAAA==.Drywar:BAACNQAFFH8OAAIPAAUKHhqWEQCgAQAPAAUKHhqWEQCgAQA1AAQKfyEAAg8ACQqqImY3AOMCAA8ACQqqImY3AOMCAAAA.Dràgonkíng:BAAANQADCgcIKQAAAA==.',
Dt='Dtinnel:BAABNQAECn8bAAIPAAgKThHQlwDcAQAPAAgKThHQlwDcAQABNQAFFAMIBwAaAJIcAA==.',
['Dà']='Dànger:BAAANQAECgYIDAAAAA==.',
Ef='Efran:BAAANQABCgIIAgAAAA==.',
Eg='Ego:BAABNQAECn8lAAIPAAkKqB3+NADrAgAPAAkKqB3+NADrAgAAAA==.',
Ei='Eisla:BAABNQAECn8cAAIHAAcKbRRvOwDfAQAHAAcKbRRvOwDfAQAAAA==.',
El='Elfor:BAAANQADCgMIAwABNQAECgkJHAAKAEgTAA==.',
Em='Emmone:BAAANQAECgQICAAAAA==.',
Ex='Exacerbator:BAAANQADCgYIGAAAAA==.',
Fa='Falcon:BAAANQABCgQIBQAAAA==.Fargecia:BAAANQAECgYICQAAAA==.Faunna:BAABNQAECn8yAAIGAAkK6Rl1IADHAgAGAAkK6Rl1IADHAgAAAA==.',
Fe='Fearbomb:BAAANQADCgQIBAAAAA==.Feath:BAAANQADCgIIAgAAAA==.Feebeeboofae:BAABNQAECn8eAAMBAAgK5ASeJAFLAQABAAcK5ASeJAFLAQAbAAEKAABXUwAbAAAAAA==.Felaz:BAABNQAECn8rAAIBAAgKUhgulQBVAgABAAgKUhgulQBVAgAAAA==.Feoridor:BAAANQADCgIIAgAAAA==.Festy:BAAANQADCggIDgAAAA==.',
Fi='Fingerguns:BAABNQAECn8yAAMYAAkKFyKADABdAwAYAAkKFyKADABdAwAcAAUK2wa5FQDNAAAAAA==.Fionaa:BAAANQADCggIBwAAAA==.',
Fl='Floortank:BAAANQAECgUIEQAAAA==.',
Fr='Friday:BAABNQAECn8aAAIRAAgKDhieRwBAAgARAAgKDhieRwBAAgAAAA==.Frikilatar:BAAANQAECgEIAQAAAA==.Frrank:BAACNQAFFH8NAAIPAAUKsiRMCQAZAgAPAAUKsiRMCQAZAgA1AAQKfyoAAg8ACQqpJj4DAN8DAA8ACQqpJj4DAN8DAAAA.',
Ga='Galcain:BAABNQAECn8qAAMXAAkKhB/CJQD+AgAXAAgKHCLCJQD+AgAdAAcKwhihLwDNAQAAAA==.',
Go='Googleyes:BAAANQADCgYIEAAAAA==.Goremaul:BAAANQAECgEIAQAAAA==.Goss:BAAANQADCgYICAAAAA==.',
Gr='Graphene:BAAANQADCgUIEgAAAA==.Greybull:BAAANQAECgQJCwAAAA==.Griffy:BAAANQADCgQIBAAAAA==.Grimseek:BAABNQAECn8gAAIdAAcK1RjrIgAzAgAdAAcK1RjrIgAzAgABNQAFFAYIEgAVAPsOAA==.Growlyr:BAABNQAECn8gAAMaAAkKviBsGgDsAgAaAAkKviBsGgDsAgAeAAEKChggpAA+AAAAAA==.Grumandel:BAABNQAECn8eAAIDAAcKfReDDwAUAgADAAcKfReDDwAUAgAAAA==.',
Ha='Hakur:BAABNQAECn8qAAICAAgKrxFOowDVAQACAAgKrxFOowDVAQAAAA==.Halfpink:BAAANQAECgQIBgABNQAECgYIFwAGACYYAA==.Hammertóe:BAAANQADCggIGgAAAA==.Hanma:BAABNQAECn8ZAAIaAAkK1RzRHQDWAgAaAAkK1RzRHQDWAgAAAA==.Harribel:BAABNQAECn8cAAIBAAcKLgZCEQFsAQABAAcKLgZCEQFsAQAAAA==.',
He='Heiferina:BAAANQAECgcIDwAAAA==.Helixra:BAAANQAECgUICQAAAA==.Helixstorm:BAAANQAECgIIAgAAAA==.Hellcroh:BAABNQAFFH8JAAMWAAUKOgk3IAD2AAAWAAQKFgg3IAD2AAAVAAIK9QWsEwBtAAAAAA==.',
Hi='Hiyodam:BAAANQADCgUIAwAAAA==.Hiyodaw:BAAANQADCgIIAgAAAA==.Hizzon:BAAANQADCggIEwAAAA==.',
Hy='Hyperíon:BAAANQAECgEIAQAAAA==.',
Ic='Icies:BAABNQAECn8jAAIbAAcKhRU7DAD1AQAbAAcKhRU7DAD1AQAAAA==.',
Il='Ilos:BAAANQAECgYICAAAAA==.',
Im='Immafrogger:BAAANQAECgUIBQABNQAECggIHAAYAMEdAA==.',
Is='Iselle:BAAANQADCgYIBgAAAA==.Ishamaël:BAAANQADCgUIBQABNQAECgkJHwAOAHgXAA==.',
Ja='Jacora:BAAANQAECggICAAAAA==.Jailene:BAAANQAECgcIBwAAAA==.Jalian:BAAANQADCgIIAgAAAA==.Jawny:BAAANQADCgUIBQAAAA==.',
Jc='Jclif:BAABNQAECn8mAAIBAAgKEhIWvQAIAgABAAgKEhIWvQAIAgAAAA==.',
Je='Jehannum:BAABNQAECn8cAAIOAAcKGhHqewCrAQAOAAcKGhHqewCrAQAAAA==.Jessira:BAAANQAECgUJDwAAAA==.',
Jo='Jonahheal:BAABNQAECn8WAAIfAAkKRB3SGwAEAwAfAAkKRB3SGwAEAwABNQAFFAYIFQARACQgAA==.Josen:BAABNQAECn8ZAAIMAAcKUBdqHgDyAQAMAAcKUBdqHgDyAQAAAA==.',
Ka='Kach:BAAANQAECgIIAgAAAA==.Kaimi:BAAANQADCgQIEQAAAA==.Kainiy:BAAANQADCgcIHgAAAA==.Kaizenn:BAAANQADCgIIAgAAAA==.Kaladjin:BAABNQAECn8eAAQLAAgKHBJ4JAD9AQALAAgKCRJ4JAD9AQAgAAcKgAeCGwAqAQAhAAYKEgkkLgD1AAAAAA==.Katarena:BAABNQAECn8eAAIfAAgKNQlggwCNAQAfAAgKNQlggwCNAQAAAA==.Kathyra:BAEBNQAECn8uAAMWAAkKzBRFOACoAgAWAAkKzBRFOACoAgAVAAEKfwIqhgAhAAABNQAFFAMIBQASAPsBAA==.Kavax:BAABNQAECn8XAAIfAAYK1BHVjgBtAQAfAAYK1BHVjgBtAQAAAA==.',
Ke='Keel:BAAANQADCgEIAQAAAA==.Keeller:BAAANQAECgMIBAAAAA==.Keggor:BAAANQAECgEIAgAAAA==.Keleris:BAAANQADCgcIDAAAAA==.Kentyr:BAAANQADCgQIBQAAAA==.Kez:BAAANQAECgQIBAAAAA==.',
Kh='Khasket:BAAANQAECgEIAQAAAA==.',
Ki='Kinký:BAABNQAECn8fAAIPAAgK1xEbkgDrAQAPAAgK1xEbkgDrAQABNQADCgcIBwAFAAAAAA==.Kiraelis:BAABNQAECn8hAAIdAAgKNxfPJAAjAgAdAAgKNxfPJAAjAgAAAA==.',
Ko='Konvik:BAAANQADCgQICgAAAA==.Korvoh:BAABNQAECn8gAAIcAAcKFRa1CADUAQAcAAcKFRa1CADUAQAAAA==.',
Kr='Kragar:BAAANQADCgIIAgAAAA==.Kredriel:BAAANQAECgEJAQAAAA==.Krinmate:BAACNQAFFH8RAAIYAAYKWBjGBwAKAgAYAAYKWBjGBwAKAgA1AAQKfycAAxgACQonEfhjAPABABgACQrXEPhjAPABABwABQpTB/wVAMkAAAAA.Krystn:BAAANQAECgIIAgAAAA==.',
Ku='Kumaro:BAAANQABCgYIBgAAAA==.Kuurome:BAAANQADCgMIAwABNQAFFAMIBwAaAJIcAA==.',
Kw='Kwinny:BAABNQAECn8eAAIfAAkKthgLLwCoAgAfAAkKthgLLwCoAgAAAA==.',
Ky='Kyloris:BAAANQAECggIAgAAAA==.Kynthria:BAAANQAECgYIDwABNQAECgkJFgABAKgeAA==.',
['Kä']='Kämik:BAABNQAECn8cAAMXAAcKkRhFfAASAgAXAAcKkRhFfAASAgAdAAEKAACtigAyAAAAAA==.',
['Kì']='Kìn:BAAANQADCgQIBQAAAA==.',
La='Lampion:BAABNQAECn8fAAIQAAkKzQeKMAC4AQAQAAkKzQeKMAC4AQAAAA==.Landon:BAAANQADCgYIBgABNQAECggIHQAaAO8gAA==.Lasstchance:BAAANQADCggIFgAAAA==.Latinamaddog:BAABNQAECn8fAAIWAAgKIxxrSwBuAgAWAAgKIxxrSwBuAgAAAA==.',
Le='Leijona:BAAANQADCggIFQAAAA==.Lelathon:BAAANQAECggICAAAAA==.Lenard:BAAANQAECgUIBgAAAA==.Leröth:BAAANQAECgQIBQAAAA==.',
Li='Likeatrain:BAABNQAECn8cAAIiAAYKdAxYJQAUAQAiAAYKdAxYJQAUAQAAAA==.Lilwagyu:BAAANQAECgYIBgAAAA==.Linds:BAABNQAECn8UAAIfAAcKtROnbQDMAQAfAAcKtROnbQDMAQAAAA==.',
Lo='Lokininja:BAAANQAECgEIAgAAAA==.Lokki:BAAANQADCgYIBgAAAA==.Loofuh:BAAANQADCgYIBgAAAA==.',
Lt='Ltdanslegs:BAABNQAECn8gAAILAAkKixpVFgCZAgALAAkKixpVFgCZAgAAAA==.',
Lu='Luardreu:BAAANQADCgQIBAAAAA==.Luxu:BAABNQAECn8uAAIjAAkK5yASDgA+AwAjAAkK5yASDgA+AwAAAA==.Luxzy:BAAANQAECgIIAwAAAA==.',
Ma='Magdog:BAAANQADCgEIAQAAAA==.Magicbarbee:BAAANQADCgYJDAAAAA==.Makarich:BAAANQAECgQICAAAAA==.Malachron:BAAANQAECgYIDgAAAA==.Manbearcat:BAABNQAECn8XAAIGAAYKJhjvSgC2AQAGAAYKJhjvSgC2AQAAAA==.Manzanoso:BAAANQADCgcIEQAAAA==.Marbleous:BAABNQAECn8nAAIPAAgKTSAIPQDRAgAPAAgKTSAIPQDRAgAAAA==.',
Mc='Mcpink:BAAANQADCgUICQABNQAECgYIFwAGACYYAA==.',
Me='Meatcurtains:BAAANQADCgUIBQABNQAECggIHQAaAO8gAA==.Melancholic:BAAANQADCggICQABNQAECgQICAAFAAAAAA==.Memisstotem:BAABNQAECn8cAAMRAAkK4Qu4eACdAQARAAgKTQy4eACdAQAOAAUKAhI6sAAuAQAAAA==.Merle:BAABNQAECn8lAAMPAAkK1x9DLgACAwAPAAkK1x9DLgACAwANAAUKPxn6FwAcAQAAAA==.',
Mi='Minaxy:BAABNQAECn80AAICAAkKJB+CKQAeAwACAAkKJB+CKQAeAwAAAA==.Miranza:BAAANQAECgQIBAAAAA==.Mistborn:BAAANQAECgYICwABNQAECgcIFwABAMMaAA==.Mistsofpoly:BAAANQAECgEIAQABNQAFFAUIEAARAB0OAA==.Mizzon:BAAANQADCgMIAwAAAA==.',
Mo='Momoku:BAABNQAECn8eAAIDAAcKWB4rCwB7AgADAAcKWB4rCwB7AgAAAA==.Moolimbo:BAAANQAECgUIBQABNQAECggIJwAGAOwTAA==.Mootalstrike:BAAANQAECgcIEwAAAA==.Moshworm:BAABNQAECn8eAAIGAAcKqQgMZAA5AQAGAAcKqQgMZAA5AQAAAA==.',
Mu='Muramasa:BAAANQAECgcIBwABNQAFFAMIBwAaAJIcAA==.',
Mv='Mvp:BAAANQADCgcIEAAAAA==.',
Na='Nalaxx:BAAANQABCgQIBAAAAA==.Namis:BAAANQAECgQIBQAAAA==.',
Ne='Nelaphim:BAABNQAECn8bAAMbAAcKFhtiCwAIAgAbAAcKFhtiCwAIAgABAAYK2AvmGgFbAQAAAA==.Nexassin:BAAANQAECgEIAQAAAA==.',
Ni='Nico:BAABNQAECn8WAAIXAAgKxRqtQQCkAgAXAAgKxRqtQQCkAgAAAA==.Nightfang:BAAANQADCggIBQAAAA==.Nimz:BAAANQAECgUIDgABNQAECggIHQAaAO8gAA==.',
No='Noctrine:BAAANQADCgQICAAAAA==.Noxxidari:BAABNQAECn8hAAIQAAkKtRYDGQCQAgAQAAkKtRYDGQCQAgAAAA==.Noxxus:BAABNQAECn8XAAIMAAgKrBOeIwDAAQAMAAgKrBOeIwDAAQABNQAECgkJIQAQALUWAA==.',
Ny='Nymphis:BAAANQADCgQIBgAAAA==.Nymunandria:BAAANQADCgUIBQAAAA==.Nymz:BAAANQAECgEIAQABNQAECggIHQAaAO8gAA==.',
Ob='Oblivia:BAAANQADCggIBAAAAA==.Obsidiansoul:BAAANQADCgcICwAAAA==.',
On='Onagne:BAAANQAECgEIAQABNQAECgkJKQAPAD8eAA==.Onepunch:BAAANQADCgcIBwAAAA==.',
Or='Orchist:BAABNQAECn8XAAINAAYKTh5ACwANAgANAAYKTh5ACwANAgAAAA==.Orimbo:BAABNQAECn8nAAMGAAgK7BN9WwBgAQAGAAYK7RB9WwBgAQAEAAMKCQWfZABtAAAAAA==.',
['Oð']='Oðynn:BAAANQAECggICAABNQAECgIIAgAFAAAAAA==.',
Pa='Paidu:BAACNQAFFH8NAAMKAAUKPQ4sDQA2AQAKAAQKthMsDQA2AQAQAAEKSwO4FwA1AAA1AAQKfyIAAwoACQpmGqwnAF0CAAoACAopGqwnAF0CABAACAqzCqQzAKEBAAAA.Palaritaz:BAAANQAECgIIBAABNQAECgcIFwABAMMaAA==.',
Pe='Pestilancé:BAABNQAECn8gAAIeAAcKPAMPbQDhAAAeAAcKPAMPbQDhAAAAAA==.',
Ph='Phenothal:BAAANQADCgQIBAAAAA==.',
Pi='Pinktp:BAAANQAECgIIAgAAAA==.Pion:BAAANQADCgQIBAAAAA==.Pitchblende:BAABNQAECn8oAAIfAAgKhRHOZgDgAQAfAAgKhRHOZgDgAQAAAA==.',
Po='Polylock:BAAANQAECggIBQAAAA==.Portiaa:BAAANQAECgcIDgAAAA==.',
Pr='Prangkim:BAAANQADCgUICwAAAA==.Protagoras:BAAANQADCgQIBAAAAA==.',
Pu='Purejoy:BAAANQAECgQIBQAAAA==.',
Qu='Quickslice:BAAANQADCgcJBwAAAA==.Quillz:BAAANQAECgQIDQAAAA==.',
Ra='Rajak:BAAANQADCgMIAwAAAA==.Rathidk:BAACNQAFFH8MAAIjAAUKgR0aCgCyAQAjAAUKgR0aCgCyAQA1AAQKf0EAAiMACQq0JBkGAJIDACMACQq0JBkGAJIDAAAA.',
Re='Redine:BAAANQADCgcICgAAAA==.Reen:BAAANQADCgcICQAAAA==.Rellt:BAAANQAECgEIAQAAAA==.Rendis:BAAANQAECgQIBQAAAA==.',
Rh='Rhayge:BAABNQAECn8gAAMIAAcK9hCUGADYAQAIAAcK9hCUGADYAQARAAUK4gc3zwDEAAAAAA==.',
Ri='Riemann:BAAANQABCggICwAAAA==.',
Ro='Roxas:BAAANQADCgIIAgAAAA==.',
Ru='Ruukia:BAACNQAFFH8HAAIaAAMKkhxwDwAQAQAaAAMKkhxwDwAQAQA1AAQKf0MAAhoACQqcJXIHAIgDABoACQqcJXIHAIgDAAAA.',
Sa='Saboo:BAABNQAECn8lAAIkAAgKOhd7BgBEAgAkAAgKOhd7BgBEAgAAAA==.Sahki:BAAANQADCgUIDAAAAA==.Saltybreath:BAABNQAECn8gAAITAAcKIBdtHQD1AQATAAcKIBdtHQD1AQABNQAECgkJIAALAIsaAA==.Sapientia:BAAANQAECgYIEgAAAA==.Savagex:BAAANQADCgMIAwAAAA==.',
Sc='Scottkill:BAAANQADCggIDAABNQAFFAcIFgABACwSAA==.',
Se='Seasnan:BAAANQAECgEIAQAAAA==.Segur:BAAANQABCgIIAgAAAA==.Seluna:BAAANQAECgcIEgAAAA==.Senapally:BAAANQADCgQIBAABNQAECgcIGAAXAM4eAA==.Senlock:BAAANQABCgIIAgABNQAECgcIGAAXAM4eAA==.',
Sh='Shadizzon:BAAANQADCgQIBAAAAA==.Shadowcloak:BAAANQABCgMIAwAAAA==.Shadowdeath:BAABNQAECn8iAAIeAAgK1wRuXgAkAQAeAAgK1wRuXgAkAQAAAA==.Shadowheàrt:BAAANQAECgUICwAAAA==.Shadowshifty:BAAANQADCgcJBwAAAA==.Shadowtotem:BAAANQAECgYICAAAAA==.Shagi:BAAANQADCgcIFQAAAA==.Shamdü:BAABNQAECn82AAIPAAkKECIhFgBgAwAPAAkKECIhFgBgAwAAAA==.Shanson:BAAANQAECgYICwAAAA==.Sharroz:BAAANQAECgIIBAAAAA==.Shizuuku:BAAANQADCgEIAQABNQAFFAMIBwAaAJIcAA==.Shockybalboa:BAAANQAECgYIDwAAAA==.Showerthots:BAAANQADCggIIAAAAA==.',
Si='Silvver:BAAANQADCgcIBwAAAA==.Sineth:BAAANQADCggIEAAAAA==.',
Sk='Skooda:BAABNQAECn8pAAIOAAkKbRLaTwA1AgAOAAkKbRLaTwA1AgAAAA==.Skybles:BAAANQAECgIIAgAAAA==.Skyded:BAAANQADCgUIBQAAAA==.Skyfell:BAABNQAECn8lAAIQAAgK2BWOJgAOAgAQAAgK2BWOJgAOAgAAAA==.Skyknight:BAAANQAECgcIEwAAAA==.',
Sl='Sloan:BAAANQADCgMIAwAAAA==.',
Sn='Snapahead:BAAANQAECgEIAQAAAA==.Sneakpeak:BAAANQABCgQIBgAAAA==.',
So='Solcon:BAAANQAECgYIEwAAAA==.Solence:BAAANQADCggIEwAAAA==.Somebodie:BAAANQAECgIIAwAAAA==.',
Sp='Spaazz:BAABNQAECn8fAAICAAcKjxjvmADsAQACAAcKjxjvmADsAQAAAA==.Sparkwire:BAAANQADCggICAAAAA==.',
Sq='Squeakbolt:BAAANQADCgcIDwAAAA==.',
St='Starofdreams:BAAANQADCgEIAQABNQAECgkJIwAYAJELAA==.Staroflight:BAAANQADCgMIAwABNQAECgkJIwAYAJELAA==.Starweaver:BAABNQAECn8jAAMYAAkKkQuRZgDoAQAYAAkKkQuRZgDoAQAcAAEKtgG0MgAZAAAAAA==.Stormrender:BAABNQAECn8pAAMLAAgKYRNbJQD1AQALAAgKYRNbJQD1AQAhAAIKLwUgRwBJAAAAAA==.Stormsong:BAACNQAFFH8FAAIOAAMKuxG/GQDvAAAOAAMKuxG/GQDvAAA1AAQKfxkAAw4ACQqlHDA1AJ8CAA4ACQqlHDA1AJ8CABEAAwryClztAIoAAAAA.Strangecandy:BAAANQAECgYICgAAAA==.Strangrdangr:BAAANQADCgQIBAAAAA==.Strángeland:BAAANQAECgIIAgAAAA==.Störmrender:BAAANQAECgEIAQABNQAECggIKQALAGETAA==.',
Su='Suhalo:BAAANQADCgMIAwAAAA==.Sunarianna:BAAANQAECgUICQAAAA==.Superpull:BAAANQAECgUICQABNQABCgIIAgAFAAAAAA==.',
Sy='Sycla:BAABNQAECn8hAAMVAAgKmByJGACmAQAWAAYK1Rm+iQDJAQAVAAYKMBiJGACmAQAAAA==.Syedrine:BAAANQADCggIBgAAAA==.Sylas:BAAANQAECgQICAAAAA==.',
Ta='Taloriesh:BAAANQAECgQICwAAAA==.Tanazir:BAEANQAECgEIAQAAAA==.Tarok:BAAANQADCgUICgAAAA==.Tashien:BAAANQAECgUIBwAAAA==.',
Te='Tealzin:BAAANQABCgQIBQAAAA==.Techytechy:BAAANQAECgYIBgAAAA==.Teito:BAAANQAECgYIEAABNQAECggIFQACANUdAA==.Terenii:BAAANQAECgIIAgAAAA==.',
Ti='Tilamano:BAABNQAECn8jAAQWAAkKNCNpDQBhAwAWAAkK1CJpDQBhAwAVAAYK7CIHCgBWAgAkAAUKIyLvCgDAAQAAAA==.Tilatree:BAAANQAECgEIAgABNQAECgkJIwAWADQjAA==.Tillidari:BAAANQAECgEIAQABNQAECgkJIwAWADQjAA==.',
To='Tohrnarc:BAABNQAECn8bAAIBAAcKxyGpigBpAgABAAcKxyGpigBpAgAAAA==.Tookkiiee:BAAANQAECggICwAAAA==.Totem:BAAANQAECgQIBgAAAA==.Totemwebz:BAABNQAECn8XAAIRAAYKyCBgUQAdAgARAAYKyCBgUQAdAgAAAA==.',
Tr='Trenve:BAABNQAECn8gAAIEAAgKzh6nEgC2AgAEAAgKzh6nEgC2AgAAAA==.',
Ts='Tseirpa:BAAANQADCgQIBQAAAA==.',
Tu='Turbomage:BAAANQADCgcIBwAAAA==.Tuzzyfits:BAABNQAECn8nAAIRAAgKQhwnNgCEAgARAAgKQhwnNgCEAgAAAA==.',
Tw='Twojayzz:BAAANQAECggIDAAAAA==.',
Ty='Tyrethia:BAAANQAECgUIDwAAAA==.',
['Té']='Téchymoon:BAACNQAFFH8FAAIVAAMKVAKxDAChAAAVAAMKVAKxDAChAAA1AAQKfzsAAhUACQoCFooGAKICABUACQoCFooGAKICAAAA.',
Ug='Uggaibo:BAAANQADCgQIBAAAAA==.Ugo:BAAANQAECgQIBAAAAA==.',
Um='Umbron:BAABNQAECn8jAAQHAAkKcRm/GwCcAgAHAAkKDhi/GwCcAgAlAAcK9xjnHADpAQAmAAEKMA8/HAAvAAAAAA==.',
Un='Undertaker:BAAANQABCggIDAAAAA==.',
Va='Valcristo:BAABNQAECn8bAAIMAAcKYSXSDgCtAgAMAAcKYSXSDgCtAgAAAA==.Valdun:BAAANQADCgcIEQAAAA==.Vanaras:BAAANQADCgYIBwAAAA==.Vargrim:BAABNQAECn8jAAIWAAcKhwTHygAvAQAWAAcKhwTHygAvAQAAAA==.',
Ve='Venous:BAABNQAECn8cAAMHAAgK6hIASACfAQAHAAcKMBIASACfAQAlAAYKwA4gKgBuAQAAAA==.Vestt:BAAANQADCggIFQAAAA==.',
Vi='Vicariana:BAACNQAFFH8OAAMnAAUKpB1oCgBLAQAnAAQKpB1oCgBLAQAYAAMK1QJIIwC6AAA1AAQKfzUABBwACQquH4YEAH4CABwABgpnJIYEAH4CACcABwqTH7IcAFsCABgACQqgFsdPADECAAAA.Victhyr:BAAANQAECgUICQAAAA==.Vidette:BAAANQADCgYIEgAAAA==.Viduus:BAABNQAECn8dAAMaAAgK7yDwIQC9AgAaAAgK7yDwIQC9AgAeAAYK5RnEQAC+AQAAAA==.Viv:BAABNQAECn8ZAAMCAAgKZxPplwDvAQACAAgKZxPplwDvAQAfAAMKEyCVuQAFAQAAAA==.',
Vo='Vodmor:BAAANQAECgYIEgAAAA==.Voldermort:BAAANQADCgcIEwAAAA==.',
Wa='Warrendemon:BAAANQAFFAIIAgAAAA==.',
We='Wedowarcrime:BAAANQADCgIIAgAAAA==.',
Wh='Whims:BAAANQAECgUIDgAAAA==.',
Wi='Wildheart:BAAANQAECgEJAQAAAA==.Wingchún:BAAANQADCgcIBwAAAA==.',
Wo='Woregontail:BAAANQAECgIIAgAAAA==.Wowbelly:BAAANQAECgcIDgAAAA==.',
Xa='Xalrissa:BAAANQADCgUICgAAAA==.Xandeath:BAAANQAECgQIBAAAAA==.Xandem:BAAANQAECgQIBAAAAA==.Xandros:BAAANQAECgYIEAAAAA==.',
Xo='Xonk:BAACNQAFFH8GAAIkAAMKCA6oBAChAAAkAAMKCA6oBAChAAA1AAQKfykAAyQACQqkGjIEAJ8CACQACQqkGjIEAJ8CABUAAQqMG8ZnAFEAAAAA.',
Yg='Ygcamel:BAAANQADCggIEgAAAA==.',
Yi='Yiazmat:BAAANQABCgcICwAAAA==.',
Za='Zaklu:BAAANQAECgIIBAAAAA==.Zalagrimbor:BAABNQAECn8fAAMOAAkKeBc+RgBaAgAOAAkKeBc+RgBaAgARAAMKgAWj/ABrAAAAAA==.Zalathar:BAAANQABCgQIBAAAAA==.Zaps:BAABNQAECn8mAAIOAAgKxCFOIgD9AgAOAAgKxCFOIgD9AgAAAA==.Zarev:BAACNQAFFH8QAAIdAAYKchkTBgDzAQAdAAYKchkTBgDzAQA1AAQKfycAAh0ACQoAI0cNAAcDAB0ACQoAI0cNAAcDAAAA.',
Ze='Zeenab:BAAANQADCgIIAgAAAA==.Zegrath:BAAANQADCgcJDAABNQADCgcIFQAFAAAAAA==.Zelie:BAABNQAECn8bAAMRAAcK1g5WfwCKAQARAAcK1g5WfwCKAQAOAAUK4wAWDAFsAAAAAA==.Zenreto:BAABNQAECn8gAAIHAAcK0xeuMQATAgAHAAcK0xeuMQATAgAAAA==.',
Zh='Zhuri:BAAANQADCggICAAAAA==.',
Zo='Zoeri:BAAANQAECgEIAQAAAA==.Zoltraak:BAAANQADCgYIDwAAAA==.',
['Än']='Änmoa:BAACNQAFFH8OAAIIAAUKLhwyAgC+AQAIAAUKLhwyAgC+AQA1AAQKfzAAAggACQqjJawBAJ4DAAgACQqjJawBAJ4DAAAA.',
['Ïn']='Ïnsane:BAAANQAECgIIAgAAAA==.',
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
