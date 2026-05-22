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

local lookup = {'Druid-Restoration','Warrior-Fury','Warrior-Arms','Mage-Frost','DemonHunter-Devourer','Unknown-Unknown','Hunter-Survival','Shaman-Enhancement','Shaman-Elemental','Mage-Arcane','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','Paladin-Retribution','Druid-Balance','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Shaman-Restoration','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Evoker-Preservation','Paladin-Protection','Warlock-Affliction','Paladin-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Fire','Priest-Discipline','Warrior-Protection','DeathKnight-Frost','Rogue-Outlaw','Druid-Feral','Rogue-Assassination','Druid-Guardian',}
local provider = {region='US',realm='Spirestone',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abadon:BAAALgAECgUJBQAAAA==.',
Ac='Aciddeath:BAAALgAECgYJDAAAAA==.Acye:BAAALgAECgIJAgAAAA==.',
Ad='Admaris:BAABLgAECn8UAAIBAAYJFB1mOwC3AQABAAYJFB1mOwC3AQAAAA==.',
Ag='Age:BAABLgAECn8jAAMCAAkJbBvNEgAUAgACAAkJbBvNEgAUAgADAAMJnw0QJwC2AAAAAA==.Agni:BAACLgAFFH8cAAIEAAYJtR1KEgDDAQAEAAYJtR1KEgDDAQAuAAQKfyUAAgQACQnnI6gEALYDAAQACQnnI6gEALYDAAAA.',
Ai='Ainslee:BAAALgADCgMJAwAAAA==.',
Aj='Ajoblanco:BAAALgAECgQJBQAAAA==.',
Ak='Akkadian:BAABLgAECn8oAAICAAkJLRc7EwAQAgACAAkJLRc7EwAQAgAAAA==.',
Al='Alavendis:BAABLgAECn8VAAIFAAcJRRxnNACrAQAFAAcJRRxnNACrAQABLgAECgQJBgAGAAAAAA==.Alexá:BAAALgAECgUJCQABLgAECgcJIAAHAB4hAA==.Almight:BAAALgAECgMJBQAAAA==.Alnasham:BAACLgAFFH8TAAMIAAUJQh2mAADMAQAIAAUJQh2mAADMAQAJAAEJyAEROgA7AAAuAAQKfyoAAwgACAmUIpEEAFcCAAgACAmUIpEEAFcCAAkAAQmUBpOEACQAAAAA.Alphashadow:BAAALgAECgQJBAAAAA==.Alvoka:BAABLgAECn8cAAMEAAkJyhOVagAAAgAEAAkJyhOVagAAAgAKAAQJpQ+SBwDqAAAAAA==.',
Am='Amarillos:BAAALgAECgkJEAAAAA==.Amarillys:BAACLgAFFH8JAAILAAQJpBdzCwCsAAALAAQJpBdzCwCsAAAuAAQKfyMAAwsACQlDHRkOAHoCAAsACQlDHRkOAHoCAAwAAQnYFJZjADEAAAAA.Ambrotos:BAAALgAECgYJDwAAAA==.Amither:BAAALgAECgYJBgAAAA==.Ammutseba:BAABLgAECn8pAAMNAAkJFhqfBQD2AQANAAkJFhqfBQD2AQAFAAEJXQrJ4gAlAAAAAA==.Amperage:BAAALgAECgEJAQAAAA==.',
An='Anfall:BAAALgAECgkJDgAAAA==.Angermeier:BAABLgAECn8nAAICAAgJCRwyEgAaAgACAAgJCRwyEgAaAgAAAA==.Angryjeid:BAAALgAECgYJBgABLgAFFAMJCQAOAGUSAA==.Angrylady:BAAALgAECgEJAgAAAA==.Anohru:BAAALgADCgYJBgAAAA==.',
Ar='Archamdrag:BAAALgAECggJEQAAAA==.Archituethis:BAAALgAECgEJAgAAAA==.Arg:BAAALgAECgYJBwAAAA==.Arowin:BAABLgAECn8YAAIPAAgJvxFBHgB9AQAPAAgJvxFBHgB9AQAAAA==.Arrielle:BAAALgAECgYJBgAAAA==.Arthaniis:BAACLgAFFH8IAAIJAAMJhhv0GgD9AAAJAAMJhhv0GgD9AAAuAAQKfxwAAgkACAnMIP8IAAIDAAkACAnMIP8IAAIDAAAA.',
As='Asdar:BAAALgADCgEJAQAAAA==.',
At='Athlina:BAAALgAECgYJDAAAAA==.Attackheli:BAAALgAECgQJCAAAAA==.',
Au='Audideath:BAAALgAECgYJEQAAAA==.Audry:BAAALgADCgcJCQAAAA==.Augtistic:BAABLgAECn8bAAMQAAkJShJIHQDcAQAQAAkJShJIHQDcAQARAAYJcwIJKwDFAAABLgAECgkJJQASABUfAA==.Auurdeath:BAAALgAECgYJCgAAAA==.',
Av='Avidswolf:BAABLgAECn8lAAIEAAcJeA+IfABDAQAEAAcJeA+IfABDAQAAAA==.Avãcyn:BAABLgAECn8kAAMDAAgJ6wp8GwAlAQADAAgJ6wp8GwAlAQACAAYJSwaESQDOAAAAAA==.',
Aw='Aw:BAACLgAFFH8SAAITAAcJdSI7AAAUAgATAAcJdSI7AAAUAgAuAAQKfxgAAhMACAmeJo0BAJEDABMACAmeJo0BAJEDAAAA.Awppenheimer:BAABLgAECn8hAAMUAAkJ6x1tIwAXAgAUAAgJFRxtIwAXAgAVAAYJdRyOEADKAQAAAA==.',
Ax='Ax:BAECLgAFFH8RAAMSAAUJpBF5SQDXAAASAAQJpBF5SQDXAAAWAAEJAABLPgAAAAAuAAQKfxkAAhIABwl0HP5ZAHIBABIABwl0HP5ZAHIBAAAA.',
Ay='Ayesh:BAAALgADCgkJCQAAAA==.',
Az='Azuro:BAAALgAFFAMJAwAAAA==.',
Ba='Babycarrots:BAAALgAECgcJCAAAAA==.Baconz:BAABLgAECn8cAAMJAAkJPxRwJADtAQAJAAkJPxRwJADtAQAXAAEJ/QJQqQAiAAAAAA==.Bakeon:BAABLgAECn8dAAMXAAgJ1hXqJADbAQAXAAgJ1hXqJADbAQAJAAMJYAQidABxAAAAAA==.Bakkaz:BAAALgADCgYJBgAAAA==.Baldozhi:BAAALgAECgYJCwAAAA==.Bangbang:BAAALgAFFAEJAQAAAA==.Barrikade:BAAALgAECgIJAgAAAA==.Batareva:BAAALgAECgQJEgAAAA==.',
Be='Bearbeem:BAAALgAECgMJAwABLgAECggJGwAYAB8QAA==.Beardcheese:BAAALgAECgIJAQAAAA==.Benita:BAAALgAECgEJAQAAAA==.Benson:BAACLgAFFH8IAAIZAAUJjQL/KQDLAAAZAAUJjQL/KQDLAAAuAAQKfyAAAxkACAmQFR0cAIkBABoABgk6HSYdAPEBABkACAkAEB0cAIkBAAAA.',
Bi='Bink:BAABLgAECn8ZAAIHAAkJ9xo1BADcAgAHAAkJ9xo1BADcAgAAAA==.Birblock:BAABLgAFFH8LAAMUAAUJDxeWLgAzAQAUAAUJBxeWLgAzAQAVAAEJWQvsGgBGAAABLgAFFAkJJAAHAEIZAA==.Birch:BAAALgADCgQJBAAAAA==.',
Bl='Blaid:BAABLgAECn8cAAIFAAYJdggUhADFAAAFAAYJdggUhADFAAAAAA==.Bloric:BAAALgADCgMJBAAAAA==.Blucifur:BAABLgAECn8ZAAMbAAkJCQm/OAD4AAAbAAgJEge/OAD4AAAZAAIJchj/aABHAAAAAA==.Blãckheart:BAAALgAECgEJAQAAAA==.',
Bo='Bobbo:BAAALgAECgQJBwAAAA==.Bobsaggot:BAAALgAECgMJAwAAAA==.Bodom:BAAALgADCgEJAgAAAA==.Bolterguy:BAAALgADCgkJCQAAAA==.Boomin:BAAALgAECggJDgAAAA==.',
Br='Braass:BAAALgAECgQJBgABLgAECgQJEgAGAAAAAA==.Breachnclear:BAAALgAECgYJBwAAAA==.Brek:BAAALgAECgYJCgAAAA==.Brewsack:BAAALgADCgYJEAAAAA==.Brewtherguy:BAABLgAECn8mAAIZAAkJdRq1DQAgAgAZAAkJdRq1DQAgAgAAAA==.Brochacho:BAAALgADCgEJAQAAAA==.Browndog:BAAALgAECgYJBgAAAA==.Bruceshepard:BAAALgAECgQJBAABLgAECgcJFQAOAOsVAA==.Bruiser:BAAALgADCgEJAQAAAA==.Brutebuffalo:BAABLgAECn8fAAIXAAkJmSDSBAAiAwAXAAkJmSDSBAAiAwAAAA==.Brutechaos:BAAALgADCgQJBAABLgAECgkJHwAXAJkgAA==.Bruteflappy:BAAALgADCgkJCQABLgAECgkJHwAXAJkgAA==.',
Bu='Buffygirl:BAABLgAECn8bAAMQAAgJ8BXQGwCoAQAQAAgJ8BXQGwCoAQAcAAUJcg0KJQB2AAAAAA==.Bustle:BAAALgADCgkJCQAAAA==.',
Bw='Bwonsambwe:BAAALgAECgEJAQAAAA==.',
['Bâ']='Bâra:BAAALgAECgkJEgAAAA==.',
['Bå']='Båne:BAABLgAECn8kAAIFAAgJlg2GUQBDAQAFAAgJlg2GUQBDAQAAAA==.',
Ca='Carnal:BAAALgADCgUJCAAAAA==.Casini:BAAALgADCgMJAwAAAA==.Caydened:BAAALgAECgMJAwAAAA==.Cazic:BAAALgAECgYJDgAAAA==.',
Ce='Cedren:BAACLgAFFH8IAAIFAAMJlhniPADoAAAFAAMJlhniPADoAAAuAAQKfxkAAgUACQnbHfEdAJ4CAAUACQnbHfEdAJ4CAAAA.Celerius:BAAALgADCgEJAQAAAA==.Celeste:BAAALgAECgEJAQAAAA==.Cerari:BAABLgAECn8XAAIFAAcJsyKpIQCHAgAFAAcJsyKpIQCHAgAAAA==.Certified:BAAALgAECgYJBwAAAA==.',
Ch='Chalix:BAAALgAECgEJAQAAAA==.Cheapheal:BAACLgAFFH8HAAIPAAQJCBhkDgBOAQAPAAQJCBhkDgBOAQAuAAQKfzgAAw8ACQk6JLACABUDAA8ACQk6JLACABUDAAEABglWGWspAMMBAAAA.Cheaptide:BAAALgAECgcJBwAAAA==.Cheburashka:BAACLgAFFH8TAAIJAAYJ5iBOBgC5AQAJAAYJ5iBOBgC5AQAuAAQKfxcAAgkACAnNIhAPALYCAAkACAnNIhAPALYCAAAA.Chewymentos:BAAALgAECgUJDwABLgAECggJKQAdABwMAA==.Chimerabob:BAAALgAECgYJDwAAAA==.Chunkyhunter:BAAALgAECgYJBgABLgAFFAUJEQAaAMIcAA==.Chunkymonkey:BAACLgAFFH8RAAMaAAUJwhySBwBUAQAaAAUJwhySBwBUAQAZAAIJGA65HACKAAAuAAQKfxsAAxoACAlKIS4LAMcCABoACAlKIS4LAMcCABkABQlxGuw9AE4BAAAA.',
Ci='Cidren:BAAALgAECgIJAwAAAA==.',
Cj='Cjpriestly:BAAALgADCgcJBwAAAA==.',
Cl='Clappncheeks:BAABLgAECn8gAAIHAAcJPB8zEADtAQAHAAcJPB8zEADtAQAAAA==.Claudefrollo:BAABLgAECn8bAAIPAAYJRBCgNADtAAAPAAYJRBCgNADtAAAAAA==.',
Co='Como:BAAALgADCgMJAwAAAA==.Corlem:BAAALgAECgUJBgAAAA==.Corrüpt:BAAALgAECggJEgAAAA==.',
Cr='Crimsa:BAABLgAECn8qAAIeAAkJ5Qc/CQBlAQAeAAkJ5Qc/CQBlAQAAAA==.Crimsongost:BAAALgAECgQJBwAAAA==.Crixsonaxle:BAAALgAECgIJAgAAAA==.Cryogen:BAABLgAECn8ZAAIPAAgJJiCtEgDvAQAPAAgJJiCtEgDvAQAAAA==.',
Cs='Cs:BAABLgAECn8pAAIZAAkJzCLSAwBSAwAZAAkJzCLSAwBSAwAAAA==.',
Cu='Curufin:BAAALgAECgUJCwAAAA==.',
Da='Daddysmooth:BAAALgAECgYJCAAAAA==.Daemon:BAABLgAECn8iAAISAAkJsyF/DgC9AgASAAkJsyF/DgC9AgAAAA==.Daemonproph:BAABLgAECn8dAAITAAcJyhOXFgBtAQATAAcJyhOXFgBtAQAAAA==.Dakini:BAABLgAECn8ZAAIfAAcJWiRtDACBAgAfAAcJWiRtDACBAgAAAA==.Daktaklakpak:BAABLgAFFH8KAAQgAAMJOBlIRgCoAAAHAAIJhBLJGQCqAAAgAAIJDxpIRgCoAAAhAAEJihfYIQBJAAAAAA==.Dalmighty:BAAALgAECgQJCAAAAA==.Dam:BAABLgAECn8mAAIdAAkJ1B9WBADDAgAdAAkJ1B9WBADDAgAAAA==.Dangerruss:BAABLgAECn8bAAIdAAgJyRKuEQBTAQAdAAgJyRKuEQBTAQAAAA==.Darkhaven:BAAALgADCgIJAgAAAA==.Darksouls:BAAALgADCgUJBQAAAA==.Darkspartan:BAACLgAFFH8OAAIiAAQJhxx1AAB4AQAiAAQJhxx1AAB4AQAuAAQKfx4AAyIACAn1HSABAMACACIACAn1HSABAMACAAQABAkrCGYZAcwAAAAA.Dasmonkey:BAAALgAECgIJAgAAAA==.Daxos:BAABLgAECn8mAAIEAAkJ9BhTMwALAgAEAAkJ9BhTMwALAgAAAA==.',
De='Deathcast:BAAALgADCgEJAQAAAA==.Deathith:BAAALgAECgEJAQAAAA==.Deathplague:BAAALgADCgcJEgAAAA==.Deelahn:BAABLgAECn8YAAMLAAgJzQhhKgAtAQALAAgJzQhhKgAtAQAMAAEJXAD4bwAXAAAAAA==.Demideudle:BAAALgAECgEJAQAAAA==.Demonicchoas:BAABLgAECn87AAMVAAkJiSAaAQAmAwAVAAgJJyIaAQAmAwAUAAcJdBstHgA0AgAAAA==.Denagorn:BAACLgAFFH8IAAMOAAQJAQ7fJwAzAQAOAAQJ5g3fJwAzAQAdAAMJeQZ7CQCKAAAuAAQKfzwAAg4ACQluHRQYANgCAA4ACQluHRQYANgCAAEuAAUUBgkdABIAWRkA.Denlen:BAAALgADCgIJAgAAAA==.Depressos:BAABLgAECn8WAAIBAAkJ3x+6BQArAwABAAkJ3x+6BQArAwAAAA==.Deutzfr:BAABLgAECn8WAAMNAAcJLBavEwDDAAAFAAcJaROocgBNAQANAAUJLw2vEwDDAAAAAA==.',
Di='Dizzleman:BAAALgAECgkJAgAAAA==.',
Do='Dominant:BAABLgAECn8jAAIEAAkJkR3ZGQCGAgAEAAkJkR3ZGQCGAgAAAA==.Dooma:BAABLgAFFH8MAAMUAAgJ8BGiCwDAAQAUAAcJ4hGiCwDAAQAeAAIJSxNMBQCxAAAAAA==.Dorgie:BAAALgAFFAEJAQABLgAFFAIJBAAGAAAAAA==.Dotdotnuke:BAAALgADCgYJCAAAAA==.Dotorgz:BAABLgAECn8eAAIEAAgJSiHeIQDsAgAEAAgJSiHeIQDsAgAAAA==.',
Dr='Draco:BAAALgADCgEJAQAAAA==.Drag:BAAALgAECgQJBgAAAA==.Dragon:BAABLgAECn8YAAIcAAkJFhBdFgDoAQAcAAkJFhBdFgDoAQAAAA==.Dragowolf:BAAALgADCgYJBgAAAA==.Drbob:BAAALgAECgQJBgAAAA==.Drifting:BAAALgADCgMJAwAAAA==.Drimbatbitak:BAAALgAFFAMJBAABLgAFFAYJFAAfAM0jAA==.Drock:BAABLgAECn8eAAIFAAgJjx3UGQA5AgAFAAgJjx3UGQA5AgAAAA==.Druidgale:BAABLgAECn8jAAIBAAkJowseRAA4AQABAAkJowseRAA4AQAAAA==.Druidless:BAAALgAECgUJCwAAAA==.Drunkanxiety:BAABLgAECn8aAAIZAAkJ2hQPEAACAgAZAAkJ2hQPEAACAgAAAA==.Drybonez:BAABLgAECn8ZAAMJAAcJ5BOxMwAVAQAJAAYJFxexMwAVAQAXAAQJdwamdACLAAAAAA==.Drygth:BAABLgAECn8YAAQMAAkJlyCiDgCZAgAMAAcJMCKiDgCZAgALAAcJ5BouEQATAgAjAAEJbwm+VAA4AAAAAA==.',
Du='Dubshox:BAABLgAECn8gAAIJAAgJOhznFQDmAQAJAAgJOhznFQDmAQAAAA==.',
['Dá']='Dád:BAAALgADCgEJAQAAAA==.',
Ea='Earthly:BAAALgAECgEJAwAAAA==.',
Ei='Eisador:BAABLgAECn8lAAIgAAgJCxHVQQCHAQAgAAgJCxHVQQCHAQAAAA==.',
El='Eldritch:BAAALgADCgcJBwAAAA==.Elemotional:BAABLgAECn8WAAIIAAkJsRwdBABoAgAIAAkJsRwdBABoAgAAAA==.',
Eq='Equilibrio:BAABLgAECn8jAAMkAAkJbiAxBQCFAgAkAAgJ5yExBQCFAgACAAEJHRaCbQBLAAAAAA==.',
Er='Erilee:BAAALgAECgMJAwAAAA==.',
Es='Essos:BAAALgAECgIJAgAAAA==.',
Et='Ettle:BAAALgAECgEJAQABLgAECgUJBgAGAAAAAA==.',
Ew='Ewangus:BAAALgADCgYJCAAAAA==.',
Ez='Ezailas:BAABLgAECn8gAAQHAAcJHiEUDgAHAgAHAAcJDB8UDgAHAgAhAAYJNxkAMAC1AQAgAAEJjxqmzgBAAAAAAA==.Ezeelah:BAAALgAECgMJBQAAAA==.Ezpzndaheezy:BAAALgAECgEJAQABLgAECggJIwAQAMMWAA==.',
Fa='Faelthas:BAACLgAFFH8ZAAIZAAUJ5iTHAQDvAQAZAAUJ5iTHAQDvAQAuAAQKfzEAAhkACAksJtkCAGkDABkACAksJtkCAGkDAAAA.Fathercoast:BAABLgAECn8tAAMMAAkJlBxVDQAyAgAMAAkJlBxVDQAyAgAjAAcJaRr0HwCUAQAAAA==.Fauxflow:BAAALgAECgEJAQAAAA==.',
Fe='Felagund:BAAALgADCggJCAAAAA==.Felawful:BAABLgAECn8YAAMFAAkJpx1jCwC0AgAFAAkJpx1jCwC0AgANAAIJ7R2SFgClAAAAAA==.Felstrider:BAAALgAECgUJCAAAAA==.Fembouyant:BAABLgAECn8XAAIlAAkJtBSIBAAVAgAlAAkJtBSIBAAVAgAAAA==.Ferador:BAACLgAFFH8XAAMhAAYJZhNqDwDyAAAgAAMJAh5iMQD6AAAhAAUJZwVqDwDyAAAuAAQKfyUAAyEACAkEIAIjAA4CACEACAnFFQIjAA4CACAABQmKId5IAG8BAAAA.',
Fi='Figgly:BAAALgADCgYJCgAAAA==.Fistsphoyou:BAAALgAECgEJAQAAAA==.',
Fl='Flowmo:BAAALgAECgYJBwABLgAECggJFwAZANobAA==.',
Fo='Forsakken:BAAALgAECgUJBQAAAA==.Fortou:BAAALgADCgMJAgAAAA==.Fourbees:BAAALgAECgYJDQAAAA==.',
Fr='Frizly:BAABLgAECn8dAAMLAAgJ2QaILgASAQALAAgJ2QaILgASAQAMAAEJ5ACEcAAQAAAAAA==.Fromjoy:BAAALgADCgEJAQAAAA==.Frostborné:BAAALgADCgYJBgAAAA==.Frozendoinks:BAABLgAECn8XAAIEAAkJ/hGTXQAhAgAEAAkJ/hGTXQAhAgAAAA==.',
Fu='Funnylegs:BAAALgAECgEJAQAAAA==.',
Ga='Galdrell:BAABLgAECn8UAAMdAAcJaQ5uGgDwAAAdAAcJaQ5uGgDwAAAOAAEJggB7YQEXAAAAAA==.Garroshiv:BAAALgADCgEJAQAAAA==.Gateway:BAAALgAECgEJAQAAAA==.',
Ge='Gearshift:BAAALgADCgIJAgAAAA==.',
Gh='Ghouul:BAAALgADCgQJBAAAAA==.',
Gi='Ginnobli:BAAALgADCgMJBgAAAA==.Gipsydanger:BAABLgAECn8nAAMSAAkJKh9LEwAIAwASAAkJKh9LEwAIAwAlAAUJRRt4HQBRAAAAAA==.',
Gn='Gnnome:BAABLgAECn8eAAIEAAgJDgoydgBPAQAEAAgJDgoydgBPAQAAAA==.',
Go='Gog:BAAALgAECggJDwAAAA==.Goodolruss:BAAALgADCgUJBQAAAA==.Googobblers:BAAALgAECgEJAQAAAA==.Goredrinker:BAABLgAECn8iAAIWAAkJ3yVfAADPAwAWAAkJ3yVfAADPAwAAAA==.',
Gr='Graygkl:BAABLgAECn8nAAISAAkJHRyIJgAjAgASAAkJHRyIJgAjAgAAAA==.Grimaldus:BAABLgAECn8ZAAIdAAkJah98BAC9AgAdAAkJah98BAC9AgAAAA==.Grimmortal:BAAALgAECggJCAAAAA==.Grimreaper:BAABLgAECn8qAAMmAAkJuR8oAQDCAgAmAAkJuR8oAQDCAgAYAAIJeRA0UwCRAAAAAA==.Groag:BAAALgAECgYJDQAAAA==.Groovytony:BAAALgAECgYJBgAAAA==.Grototh:BAAALgAECgYJBgAAAA==.Gruffles:BAABLgAECn8kAAIBAAgJWSLSCwDGAgABAAgJWSLSCwDGAgAAAA==.Grümgully:BAAALgAECgIJAwAAAA==.',
Gu='Gump:BAABLgAECn8jAAIFAAkJ4R0mGQA+AgAFAAkJ4R0mGQA+AgAAAA==.',
Ha='Haarp:BAAALgAECgQJBgAAAA==.Hamburger:BAAALgAECgYJCgAAAA==.Handicat:BAAALgADCgEJAQABLgAECggJGwAMABMTAA==.Handimage:BAAALgADCgEJAQABLgAECggJGwAMABMTAA==.Handipriest:BAABLgAECn8bAAIMAAgJExNDGgChAQAMAAgJExNDGgChAQAAAA==.Haqq:BAABLgAECn8oAAICAAkJIRFcGADfAQACAAkJIRFcGADfAQAAAA==.Harvest:BAAALgAECgMJBAAAAA==.Harveyoswald:BAAALgAECgUJCAABLgAECggJEAAGAAAAAA==.',
He='Heatthapyrex:BAAALgAECgkJCQAAAA==.Hemophilia:BAABLgAECn8zAAISAAgJjRCdTwCPAQASAAgJjRCdTwCPAQAAAA==.Herbalise:BAAALgAECgkJAQAAAA==.Heshdk:BAAALgAECgcJDAAAAA==.Heybob:BAAALgADCgYJBgAAAA==.Heydk:BAABLgAECn8gAAISAAkJcSDZDwCyAgASAAkJcSDZDwCyAgAAAA==.',
Ho='Hoafustis:BAAALgAECgEJAQAAAA==.Hobo:BAAALgAECgYJEgAAAA==.Holyassasin:BAAALgADCgEJAQAAAA==.Holydave:BAAALgAECgQJBQAAAA==.Honeyherb:BAAALgADCggJCAAAAA==.Hoodiedoes:BAAALgADCgEJAQAAAA==.Hotgothgirl:BAAALgADCgQJBAAAAA==.',
Hu='Hundard:BAAALgAECgIJAgAAAA==.',
Hy='Hydrotine:BAAALgAECgIJAgAAAA==.',
Ib='Ibetrollinya:BAABLgAECn8YAAInAAkJKiPEAAA7AwAnAAkJKiPEAAA7AwABLgAECggJJwACADEmAA==.Iblisshaytan:BAABLgAECn8XAAMTAAcJOBVBGQBRAQATAAcJOBVBGQBRAQAFAAUJJAtmmQDoAAABLgAFFAUJBgAEAHEEAA==.Ibtrollin:BAAALgAECgUJBgAAAA==.',
Ic='Icepak:BAAALgADCgUJBQAAAA==.',
Ig='Ignacious:BAABLgAECn8uAAQXAAkJCiTjAgBQAwAXAAkJCiTjAgBQAwAJAAcJUxsMHwCWAQAIAAEJVg8VLAA1AAAAAA==.Igris:BAAALgADCgcJCAAAAA==.',
Im='Imbria:BAABLgAECn8iAAInAAgJrBYICQDaAQAnAAgJrBYICQDaAQAAAA==.Immolate:BAABLgAECn8aAAQUAAkJzyEHNgA0AgAUAAcJbx8HNgA0AgAVAAUJsCKSFgCVAQAeAAEJAAAzJABhAAAAAA==.',
In='Infamous:BAAALgAECgYJCgAAAA==.Inoue:BAAALgADCgUJBQAAAA==.Intadabowl:BAAALgADCgcJEQAAAA==.',
Io='Ionissa:BAAALgAECgcJBwAAAA==.',
Ir='Ironbreaker:BAAALgAECgEJAgAAAA==.',
Is='Ischia:BAACLgAFFH8VAAILAAUJ/xBGAgCNAQALAAUJ/xBGAgCNAQAuAAQKfyIAAwsACAkdEjUgAOABAAsACAkdEjUgAOABAAwABgkbCnM+AMEAAAAA.Iseria:BAAALgADCgYJBgAAAA==.',
It='Itsraw:BAAALgAECgEJAQAAAA==.',
Ja='Jaadyn:BAACLgAFFH8FAAIYAAIJpx+nEADFAAAYAAIJpx+nEADFAAAuAAQKfxgAAhgABwliI8MXAEsCABgABwliI8MXAEsCAAAA.Jallypally:BAAALgADCggJCQAAAA==.Jamuel:BAAALgAECgkJCAAAAA==.Janokdiso:BAAALgAECgEJAQABLgAECgkJHwAEABkaAA==.Javeighqueas:BAAALgADCgQJAgABLgAFFAIJBgASAHoUAA==.',
Jc='Jch:BAACLgAFFH8aAAMgAAgJchp+AADCAQAgAAcJDBp+AADCAQAhAAEJ1hwbHQBYAAAuAAQKfyIAAyAACQlkJP0BAH8DACAACQlkJP0BAH8DACEAAQmiB06PACwAAAAA.',
Je='Jedijed:BAAALgAECgcJDAABLgAFFAMJCQAOAGUSAA==.Jedikepjr:BAACLgAFFH8JAAIOAAMJZRIkPAD2AAAOAAMJZRIkPAD2AAAuAAQKfxQAAg4ABwnUHC9BALwBAA4ABwnUHC9BALwBAAAA.',
Jo='Johnhammond:BAAALgAECgcJDAAAAA==.Jolyne:BAAALgAECgcJCgAAAA==.Joneztown:BAABLgAECn8WAAIaAAkJQRq5CwC/AgAaAAkJQRq5CwC/AgAAAA==.Jordantheorc:BAABLgAECn8nAAMgAAkJhBxFEQCvAgAgAAkJhBxFEQCvAgAhAAIJvwLsgQBAAAAAAA==.',
Jp='Jprottsoo:BAACLgAFFH8GAAIPAAIJFRQ3JgCUAAAPAAIJFRQ3JgCUAAAuAAQKfx8AAg8ACQmHHnQHAJoCAA8ACQmHHnQHAJoCAAAA.',
Jt='Jtee:BAABLgAECn8sAAMfAAgJehXzHgDAAQAfAAgJehXzHgDAAQAOAAEJbApEOQEzAAAAAA==.',
Ju='Jukkrit:BAAALgAECgEJAQAAAA==.',
Jy='Jy:BAAALgADCgMJAwAAAA==.',
Ka='Kaellthass:BAAALgAECgEJAQAAAA==.Kaged:BAAALgADCgEJAQAAAA==.Kalmya:BAABLgAECn8kAAIBAAkJ2wpbQgBAAQABAAkJ2wpbQgBAAQAAAA==.Kamahl:BAAALgAECgEJAQABLgAECgkJFgAeAFYWAA==.Karoo:BAAALgADCgYJBgAAAA==.Kataris:BAAALgAECgEJAQAAAA==.Kaynac:BAAALgADCgMJAwAAAA==.',
Ke='Kegmen:BAAALgAECgEJAgAAAA==.Keizzer:BAABLgAECn8kAAIOAAkJlh8OHgC3AgAOAAkJlh8OHgC3AgAAAA==.Kelesa:BAAALgADCgEJAQAAAA==.Keshisaru:BAABLgAECn8UAAIgAAgJehS6JgAfAgAgAAgJehS6JgAfAgAAAA==.',
Kh='Kharms:BAABLgAECn8fAAIaAAkJ5x1FCAB8AgAaAAkJ5x1FCAB8AgAAAA==.Khazra:BAAALgAECgQJBwAAAA==.',
Ki='Kinnoxen:BAAALgAECgMJAwAAAA==.',
Kl='Klunder:BAABLgAECn8fAAIXAAkJlx6YBwDvAgAXAAkJlx6YBwDvAgAAAA==.',
Kn='Knibbs:BAABLgAECn8XAAIZAAgJ2hvTFABmAgAZAAgJ2hvTFABmAgAAAA==.Knuck:BAAALgAECgIJAwAAAA==.',
Ko='Komachi:BAAALgAECgIJAwAAAA==.Korris:BAABLgAECn8fAAIgAAkJwhuEFwBPAgAgAAkJwhuEFwBPAgAAAA==.Kostik:BAAALgAECgQJBAAAAA==.',
Kr='Krelordroin:BAAALgADCgEJAQAAAA==.Kridillis:BAABLgAECn8lAAIFAAkJYBmAFgBQAgAFAAkJYBmAFgBQAgAAAA==.Krux:BAAALgAECgIJBAAAAA==.',
Ky='Kybinc:BAAALgADCgQJBAAAAA==.',
La='Lacie:BAAALgADCgkJDAAAAA==.Laennaya:BAABLgAECn8tAAIeAAgJngsYCgBSAQAeAAgJngsYCgBSAQAAAA==.Larrious:BAAALgADCgMJBQAAAA==.Latrice:BAABLgAECn8UAAIEAAYJywc5qQDyAAAEAAYJywc5qQDyAAAAAA==.Laurantalaza:BAAALgADCgIJAgAAAA==.Lawls:BAAALgAECgIJBgAAAA==.Lazyfrost:BAABLgAECn8fAAIEAAkJGRoaQAB5AgAEAAkJGRoaQAB5AgAAAA==.Lazyunholy:BAAALgADCgkJCAABLgAECgkJHwAEABkaAA==.',
Le='Lemons:BAAALgADCgEJAQAAAA==.Lethò:BAABLgAECn8dAAMfAAcJox+WEwB2AgAfAAcJox+WEwB2AgAOAAEJZA4ZPwE1AAAAAA==.Lethô:BAABLgAECn8uAAMBAAkJ0CGDAgB/AwABAAkJ0CGDAgB/AwAPAAEJOxIIZgA3AAAAAA==.Levintry:BAAALgAECgYJBgAAAA==.',
Li='Lickemlow:BAAALgAECgEJAQAAAA==.Liesx:BAAALgAECgEJAQAAAA==.Lilboothang:BAABLgAECn8ZAAIUAAgJZxPtPACqAQAUAAgJZxPtPACqAQAAAA==.Lillìth:BAAALgAECgUJBQAAAA==.Lilzarthe:BAAALgAECgUJBQABLgAECgcJFgAQAMcTAA==.Linaria:BAAALgADCgcJDQAAAA==.',
Lo='Loachella:BAAALgADCgUJBQAAAA==.Lockitator:BAAALgADCgQJBQAAAA==.Loerasdh:BAACLgAFFH8IAAIFAAMJ6iQrPwDhAAAFAAMJ6iQrPwDhAAAuAAQKfy0AAgUACQmdJBgCALcDAAUACQmdJBgCALcDAAAA.Loko:BAACLgAFFH8WAAIPAAYJGxx0BQC6AQAPAAYJGxx0BQC6AQAuAAQKfzUAAg8ACQmCJEYCACYDAA8ACQmCJEYCACYDAAAA.Lonoa:BAAALgAFFAEJAQAAAA==.Loraen:BAAALgAECgcJCQAAAA==.Louiie:BAABLgAECn8bAAIYAAgJHxCVFwCHAQAYAAgJHxCVFwCHAQAAAA==.',
Lu='Luckygrapes:BAACLgAFFH8HAAIbAAQJvwWPHADYAAAbAAQJvwWPHADYAAAuAAQKfxoAAhsACAmqHs8OAGkCABsACAmqHs8OAGkCAAAA.Lukdanuke:BAAALgAECgYJCgAAAA==.Lumi:BAAALgAECgEJAgAAAA==.Luxxus:BAAALgAECgcJCwABLgAECgkJJAAOAJYfAA==.',
Ly='Lyri:BAAALgAECgQJBQAAAA==.',
Ma='Makhtor:BAABLgAECn8bAAIJAAgJEg7RLQAzAQAJAAgJEg7RLQAzAQAAAA==.Malificent:BAAALgADCgMJAwAAAA==.Maloa:BAAALgADCgcJBwAAAA==.Malícíous:BAABLgAECn8gAAIUAAkJXA/lOwCtAQAUAAkJXA/lOwCtAQAAAA==.Mamacita:BAAALgADCgcJDQAAAA==.Mango:BAABLgAECn8UAAIaAAcJnh0NFABPAgAaAAcJnh0NFABPAgAAAA==.Mantakore:BAACLgAFFH8RAAIcAAUJzQkhDwBBAQAcAAUJzQkhDwBBAQAuAAQKfzQAAhwACAmOGe0JAP0BABwACAmOGe0JAP0BAAAA.Marcdruid:BAAALgAECgUJBgAAAA==.Maubles:BAAALgAECgYJBwABLgAFFAQJEAAdANcNAA==.',
Me='Meadöw:BAAALgAECggJDwAAAA==.Meiling:BAAALgAECgUJBQAAAA==.Meladra:BAAALgADCgcJBwAAAA==.Menopaws:BAAALgAFFAEJAQAAAA==.Mertrik:BAABLgAECn8dAAMJAAkJghu8EAChAgAJAAkJghu8EAChAgAIAAEJuBiBKQBEAAAAAA==.',
Mi='Midk:BAABLgAECn8lAAIWAAkJlx9sCwBdAgAWAAkJlx9sCwBdAgAAAA==.Mikailla:BAAALgAFFAIJAwABLgAECgEJAQAGAAAAAA==.Mikayy:BAACLgAFFH8TAAMYAAYJEiQjBACzAQAYAAUJAiUjBACzAQAoAAEJUSDCCABmAAAuAAQKfzEAAxgACQnwJAcEAL8CABgACQmGJAcEAL8CACgAAQmSJoUWAHMAAAAA.Milenko:BAABLgAECn8uAAITAAgJLSXiAgDtAgATAAgJLSXiAgDtAgAAAA==.Milly:BAAALgAECgMJBgABLgAECggJLgATAC0lAA==.Mimid:BAAALgAECgYJDgAAAA==.Mimonk:BAAALgAECgQJBAAAAA==.Minidemons:BAAALgADCgIJAgAAAA==.Minii:BAAALgAECgYJBgAAAA==.Minteafresh:BAAALgAECgEJAQAAAA==.',
Mo='Mom:BAAALgADCgcJAQAAAA==.Monstrous:BAACLgAFFH8TAAMCAAYJghRUBQCdAQACAAUJMhhUBQCdAQADAAIJrQmcGwCEAAAuAAQKfyQAAwIACAnuHe8RAMACAAIACAnuHe8RAMACAAMABAk3Gc0YADABAAAA.Moort:BAAALgAECgYJDwAAAA==.Moothafacka:BAAALgADCgcJBwAAAA==.Mordecaii:BAAALgAECgMJBAAAAA==.Morganlefay:BAAALgADCgcJEgAAAA==.Morgul:BAAALgADCgcJBwAAAA==.Mothman:BAAALgAECggJEwAAAA==.Moyana:BAAALgAECgQJBQAAAA==.',
Ms='Msbehaven:BAABLgAECn8ZAAIUAAcJOAVRlADWAAAUAAcJOAVRlADWAAAAAA==.',
Mt='Mthafknfreez:BAACLgAFFH8GAAIEAAUJcQR+XADrAAAEAAUJcQR+XADrAAAuAAQKfyMAAgQACAmvGYVBANcBAAQACAmvGYVBANcBAAAA.',
My='Mynuturchin:BAAALgAECgUJCAAAAA==.',
['Mî']='Mîg:BAABLgAECn8iAAIFAAgJcxHNTwBIAQAFAAgJcxHNTwBIAQAAAA==.',
['Mö']='Mörk:BAAALgAECgMJAwAAAA==.',
Na='Nachteule:BAAALgAECgQJBAABLgAECgQJEgAGAAAAAA==.Nahtikal:BAABLgAECn8YAAMbAAcJ/RSiIQCQAQAbAAcJ/RSiIQCQAQAaAAQJBwlSSwCJAAAAAA==.Nashath:BAAALgADCgIJAgAAAA==.Naturae:BAAALgAECgYJCAAAAA==.Naturesbeef:BAAALgADCgYJBgABLgAECgkJJwASACofAA==.',
Ne='Neytiri:BAAALgADCggJCQAAAA==.',
Ni='Nilfalath:BAAALgAECgYJCQAAAA==.Nippy:BAAALgAECgUJCgABLgAECgYJBgAGAAAAAA==.',
No='Noriva:BAAALgAECgEJAQAAAA==.Notthechosen:BAAALgAECgEJAQABLgAFFAQJCgACAE0HAA==.',
Ny='Nymeriã:BAAALgAECgUJEAAAAA==.Nymeriå:BAAALgADCggJCQAAAA==.',
Ob='Obzy:BAAALgADCgYJBgABLgAFFAIJBgASAHoUAA==.Obzz:BAACLgAFFH8GAAISAAIJehQmYgCjAAASAAIJehQmYgCjAAAuAAQKfxgAAhIACQnYGzkZAG0CABIACQnYGzkZAG0CAAAA.',
Od='Odiedude:BAAALgAECgYJBgAAAA==.Odieous:BAAALgAECggJEAAAAA==.',
Ok='Okamy:BAABLgAECn8cAAISAAkJDx+kFACMAgASAAkJDx+kFACMAgABLgAECgcJIAAHAB4hAA==.',
Om='Omeganemesis:BAAALgADCgQJBAAAAA==.',
On='Onepeonch:BAAALgADCgcJBwAAAA==.',
Oo='Oobz:BAABLgAECn8lAAMFAAgJ6hXKOAASAgAFAAgJFhTKOAASAgATAAgJfQ/OFgBqAQABLgAFFAIJBgASAHoUAA==.',
Or='Orghujon:BAAALgAECgUJCQAAAA==.',
Ot='Otterrock:BAAALgAECgUJBgAAAA==.',
Pa='Paladeez:BAAALgAECgkJEQAAAA==.Palamon:BAAALgAECgYJDAAAAA==.Pallyfrìend:BAAALgADCgQJBAAAAA==.Pandaman:BAAALgAECgQJBgAAAA==.Papadaddy:BAAALgADCgUJBQAAAA==.Parthos:BAAALgAECggJDQAAAA==.Pazaaz:BAAALgADCgQJBAAAAA==.',
Pc='Pckle:BAACLgAFFH8TAAIZAAMJESFpGQAYAQAZAAMJESFpGQAYAQAuAAQKfxsAAhkABwnWI9sJAF0CABkABwnWI9sJAF0CAAAA.',
Pe='Perry:BAAALgADCgYJBQAAAA==.Peter:BAAALgAECgEJAQAAAA==.',
Ph='Phenomenon:BAAALgAECgQJBAAAAA==.Phickle:BAAALgAFFAMJAwABLgAFFAMJEwAZABEhAA==.Phoinix:BAAALgAECgEJAQAAAA==.',
Pi='Pikachoo:BAAALgADCgQJBAAAAA==.Piyre:BAAALgAECgEJAQAAAA==.',
Pl='Plebto:BAAALgAECgkJEAAAAA==.Ploxis:BAAALgAECgYJDwAAAA==.',
Po='Pocus:BAAALgAECgkJCwABLgAECggJIQAFAHAbAA==.Pokedone:BAAALgAECgIJAgAAAA==.Polskashaman:BAABLgAECn8eAAIIAAgJaBKNDAB/AQAIAAgJaBKNDAB/AQAAAA==.Poptart:BAACLgAFFH8HAAIOAAMJCglLSADQAAAOAAMJCglLSADQAAAuAAQKfxoAAg4ACAlIFCBdAMsBAA4ACAlIFCBdAMsBAAAA.Power:BAAALgAFFAIJAgABLgAFFAUJFgAOAOUlAA==.',
Pr='Prea:BAAALgAECgUJCgAAAA==.Premiumferal:BAAALgAECgYJDgABLgAECgkJJwASACofAA==.Primecarry:BAACLgAFFH8UAAIfAAYJzSOFAgBPAgAfAAYJzSOFAgBPAgAuAAQKfyMAAx8ACAkCI6EJANcCAB8ACAkCI6EJANcCAB0ABgkfIKcKAMsBAAAA.',
Pu='Puhtater:BAAALgAECgIJAgAAAA==.Pumpmedaddy:BAAALgAECgUJBQAAAA==.Puripuri:BAAALgAECgQJBAAAAA==.Purplepillz:BAAALgAECgYJEwAAAA==.',
['Pë']='Pëpsï:BAAALgAECgcJEAAAAA==.',
Qu='Quanah:BAAALgAECgUJCwAAAA==.',
Ra='Racho:BAAALgADCgEJAQAAAA==.Rachêt:BAAALgADCgcJEAABLgAECgUJBgAGAAAAAA==.Raigko:BAAALgAECgcJCwAAAA==.Raintolin:BAAALgAECgYJEAABLgAECgkJIgASALMhAA==.Raiva:BAAALgAECgUJAwABLgAFFAMJCAASAOUOAA==.Ralis:BAAALgADCggJCQAAAA==.Randivere:BAAALgAECgEJAQAAAA==.Raspberri:BAAALgADCgYJBgAAAA==.Rassputen:BAABLgAECn8tAAIWAAkJPhldDADDAQAWAAkJPhldDADDAQAAAA==.',
Re='Redjive:BAAALgAECgMJAgAAAA==.Redonkulos:BAAALgAFFAIJBAAAAA==.Redpatriot:BAAALgADCgkJCQAAAA==.Redstar:BAAALgADCgMJAwABLgAECggJFgAZAPwPAA==.Redthorne:BAAALgADCgMJAwAAAA==.Reesespeices:BAAALgADCgUJBQAAAA==.Regi:BAACLgAFFH8KAAMMAAQJABuXCQBrAQAMAAQJABuXCQBrAQALAAMJFh5QDgASAQAuAAQKfx0AAwwACAlTIxUTAF0CAAwABwnjIxUTAF0CAAsABgnQHIEuABIBAAAA.Reliri:BAAALgAECgYJCAAAAA==.Rev:BAAALgAECgYJEAAAAA==.',
Ri='Ricflare:BAAALgADCgkJFQAAAA==.Rider:BAAALgADCgYJBgABLgAFFAYJGAAfAG8aAA==.Rinth:BAABLgAECn8hAAMhAAkJMSL6CQAEAwAhAAgJpiH6CQAEAwAgAAMJlSFHbQAMAQAAAA==.',
Ro='Roacham:BAABLgAECn8YAAIdAAgJQhpCCABWAgAdAAgJQhpCCABWAgAAAA==.Roguen:BAABLgAECn87AAIYAAkJfRR9DgDxAQAYAAkJfRR9DgDxAQABLgAFFAUJBgAEAHEEAA==.Rohunter:BAAALgADCgYJBgAAAA==.Rollout:BAAALgAECgUJBgAAAA==.Romelus:BAAALgAECgUJDQABLgAFFAMJBAAGAAAAAA==.Romirin:BAAALgAECgQJBgAAAA==.Rooky:BAAALgADCgIJAgAAAA==.Rotan:BAAALgAECgYJDwAAAA==.Roulduke:BAABLgAECn8jAAIJAAgJFBJtIQCFAQAJAAgJFBJtIQCFAQAAAA==.',
Ru='Ruenan:BAAALgADCgcJCQAAAA==.',
Ry='Rylearria:BAAALgADCgMJAwAAAA==.Ryna:BAAALgADCgkJCAAAAA==.',
['Rù']='Rùckús:BAABLgAECn8lAAISAAkJFR+2GgBkAgASAAkJFR+2GgBkAgAAAA==.Rùin:BAAALgAECgIJAgAAAA==.',
Sa='Sacredmentos:BAABLgAECn8pAAMdAAgJHAwGFwAVAQAdAAgJHAwGFwAVAQAOAAEJbgVRSQErAAAAAA==.Saintpierre:BAAALgAECgIJAgABLgAECgcJFgANACwWAA==.Sakiara:BAAALgAECgQJBgAAAA==.Sammybeans:BAABLgAECn8kAAIOAAkJMhcNMAD5AQAOAAkJMhcNMAD5AQAAAA==.Samäel:BAAALgADCgMJBQAAAA==.Sanai:BAABLgAECn8fAAIgAAgJ2R1eFABnAgAgAAgJ2R1eFABnAgAAAA==.Sandon:BAAALgADCgYJCQAAAA==.Sanghelios:BAAALgADCgkJFQAAAA==.Sapito:BAABLgAECn8UAAIWAAgJxgNFMAC+AAAWAAgJxgNFMAC+AAAAAA==.Sarelth:BAAALgADCgYJBgAAAA==.',
Sc='Scrandle:BAAALgADCgEJAQABLgADCgQJBAAGAAAAAA==.Screwball:BAAALgADCgEJAQAAAA==.',
Se='Seceron:BAAALgAECggJDwAAAA==.Sekai:BAAALgAFFAIJAgAAAA==.Selexi:BAAALgAECgYJEwAAAA==.Sereníty:BAABLgAECn8kAAMLAAgJ3gZASQAUAQALAAYJiwhASQAUAQAMAAgJNgTONADyAAAAAA==.Serpentsin:BAAALgAECgMJBAAAAA==.',
Sg='Sgtslappy:BAABLgAECn8xAAICAAkJqx/0BgCzAgACAAkJqx/0BgCzAgAAAA==.',
Sh='Shanarelle:BAABLgAECn8aAAIBAAgJzxkeHgBNAgABAAgJzxkeHgBNAgAAAA==.Shasa:BAACLgAFFH8FAAIgAAMJ0wpJOwDbAAAgAAMJ0wpJOwDbAAAuAAQKfywAAiAACQneGegZAG0CACAACQneGegZAG0CAAAA.Shazik:BAAALgAECgEJAQAAAA==.Sheroko:BAAALgAECgEJAQAAAA==.Shinanìgans:BAAALgAECgYJBgAAAA==.Shmoopy:BAAALgAECgYJBgAAAA==.Shortyman:BAAALgAECgUJBwABLgAECgkJJwASACofAA==.Shruikan:BAABLgAECn8UAAQQAAcJTRk+HADlAQAQAAcJ2Rg+HADlAQARAAcJ7g8NGQBvAQAcAAMJlgWuPACFAAAAAA==.Shötö:BAAALgADCgYJBwAAAA==.',
Si='Sicknasty:BAAALgADCgcJBwABLgAECgYJEQAGAAAAAA==.Silpknot:BAAALgADCgYJBgAAAA==.Silzo:BAACLgAFFH8IAAISAAMJ5Q4PZwCfAAASAAMJ5Q4PZwCfAAAuAAQKfyoAAxIACAl2HucqAA8CABIACAkBHOcqAA8CABYAAgkCHSZAAE0AAAAA.Sindeep:BAAALgAECgMJAwAAAA==.Sisterwife:BAAALgAECgEJAgAAAA==.Sisturfistur:BAAALgAECgQJBgAAAA==.',
Sk='Skunkpaw:BAAALgADCgYJEQAAAA==.Skysong:BAACLgAFFH8VAAMRAAYJvBFVAQCmAQARAAUJ9Q9VAQCmAQAQAAQJrwz1EgDoAAAuAAQKfyEABBEACAnJHc4MAA4CABEABwlhG84MAA4CABwABwlsF18KAPABABAAAwnVF0xCANoAAAAA.',
Sl='Slashedeye:BAABLgAECn80AAIiAAkJvxnSAQAOAgAiAAkJvxnSAQAOAgAAAA==.',
Sm='Smallfoot:BAAALgAECgEJAQAAAA==.Smellsoftree:BAAALgAECgMJAwAAAA==.',
Sn='Snowynn:BAABLgAECn8mAAMpAAkJwQ0qEwBOAQApAAkJwQ0qEwBOAQABAAEJWwHx6gAZAAAAAA==.Snubby:BAABLgAECn8kAAMVAAkJEyR0DAD7AQAUAAcJISVLJACCAgAVAAUJuCJ0DAD7AQAAAA==.',
So='Soleil:BAABLgAECn8UAAMMAAkJkg9qLAB6AQAMAAkJkg9qLAB6AQAjAAMJZRPDSABjAAAAAA==.Solheim:BAACLgAFFH8MAAMHAAQJwxe7CQBUAQAHAAQJpha7CQBUAQAhAAIJHB2jGgCvAAAuAAQKfyQAAyEACAkYI9kKAPgCACEACAkoItkKAPgCAAcABAlFHaErAPIAAAAA.Souffle:BAACLgAFFH8HAAIUAAMJIQpiWADMAAAUAAMJIQpiWADMAAAuAAQKfyIAAxQABwk5GY1FAI0BABQABwk5GY1FAI0BABUAAQkAAHVtADoAAAEuAAUUBAkOAA4ASRkA.',
Sp='Spathi:BAAALgAECgEJAQAAAA==.Spinyhush:BAABLgAECn8WAAMZAAgJ/A8ZMgCJAQAZAAgJ/A8ZMgCJAQAaAAEJ/wdxeQAsAAAAAA==.Spookypink:BAABLgAECn8ZAAIOAAkJkCJHEAANAwAOAAkJkCJHEAANAwAAAA==.Spárda:BAAALgAECgMJAwABLgAECgcJIAAHAB4hAA==.',
Sq='Squirtz:BAAALgAECgYJBgAAAA==.',
Sr='Srirachajane:BAAALgADCgkJDQABLgAECggJGQAnADAbAA==.',
St='Stabbasaurus:BAAALgAECgYJDAAAAA==.Strathin:BAAALgADCgkJDQAAAA==.Strathz:BAABLgAECn8lAAMVAAkJpCCeCgAVAgAVAAYJPx+eCgAVAgAUAAcJjh5FMQDVAQAAAA==.Stórmcaller:BAAALgADCgEJAQAAAA==.',
Su='Suggadeath:BAABLgAECn8VAAIfAAgJ1hq3GABNAgAfAAgJ1hq3GABNAgAAAA==.Summerset:BAAALgAECgYJEAAAAA==.Sushi:BAAALgAECgYJBwAAAA==.',
Sy='Sylatis:BAACLgAFFH8kAAMHAAkJQhlKAAB8AgAHAAgJoxlKAAB8AgAhAAYJiRTMAwAHAgAuAAQKfxYAAyEACAk0JVsNANsCACEACAk0JVsNANsCAAcAAwmkHggoAHUAAAAA.Sylvara:BAAALgAECgMJBgAAAA==.Sylátis:BAAALgAECgYJDAAAAA==.Sylãtis:BAAALgAECgcJDgAAAA==.',
['Sö']='Söultender:BAABLgAECn8lAAQjAAgJGBWhFgDLAQAjAAgJBg+hFgDLAQALAAUJABNQMAAFAQAMAAEJvAlNYwAyAAAAAA==.',
Ta='Taichi:BAACLgAFFH8PAAIbAAQJlhgrEwA5AQAbAAQJlhgrEwA5AQAuAAQKfyIAAhsACAkAHksMAI4CABsACAkAHksMAI4CAAAA.Talys:BAACLgAFFH8ZAAIcAAgJ+hjvAACuAgAcAAgJ+hjvAACuAgAuAAQKfyoAAhwACQlBHIcIALICABwACQlBHIcIALICAAAA.Tanrok:BAAALgADCgEJAQAAAA==.Tao:BAAALgADCgUJBQAAAA==.Tarth:BAACLgAFFH8YAAIpAAYJkSLBAAAGAgApAAYJkSLBAAAGAgAuAAQKfyMAAikACAkEJmwBAEEDACkACAkEJmwBAEEDAAAA.Tayylor:BAAALgADCgMJAwAAAA==.Tazzie:BAABLgAECn8mAAIcAAgJMxuCBgBaAgAcAAgJMxuCBgBaAgAAAA==.Taïko:BAAALgADCgQJBAAAAA==.',
Te='Tehchosen:BAAALgADCgUJBQAAAA==.Tenderbeef:BAAALgAECgYJDQABLgAECgkJIgASALMhAA==.Tenniell:BAAALgAECgQJDQAAAA==.Terrezan:BAAALgADCgMJAwAAAA==.Terrynoc:BAAALgADCgEJAQAAAA==.Tetrk:BAAALgADCgUJBQAAAA==.Texicola:BAABLgAECn8cAAIEAAkJTA+eQQDXAQAEAAkJTA+eQQDXAQAAAA==.',
Th='Thab:BAAALgAECgUJCgABLgAECggJIwAQAMMWAA==.Thabk:BAABLgAECn8jAAMQAAgJwxYxHgCXAQAQAAgJwxYxHgCXAQARAAEJaAdCQwAoAAAAAA==.Thaelorn:BAAALgAECgMJAwAAAA==.Tharit:BAAALgADCgYJCgAAAA==.Theodius:BAAALgAECgQJBAAAAA==.Theshortbuss:BAABLgAECn8VAAIOAAcJ6xXnWwByAQAOAAcJ6xXnWwByAQAAAA==.Thesuffering:BAAALgAECgUJBwAAAA==.Thesyra:BAAALgAECggJCQAAAA==.Thingtwò:BAAALgADCgUJBQAAAA==.Threepwood:BAAALgADCgEJAQAAAA==.Thurmond:BAAALgAECgQJDgAAAA==.',
Ti='Tiddybear:BAAALgAECgkJCgAAAA==.Timerunhunt:BAAALgADCgUJBgAAAA==.Timkurkjian:BAAALgADCgYJCQAAAA==.',
To='Toastay:BAABLgAECn8WAAIWAAcJSAh5JADLAAAWAAcJSAh5JADLAAAAAA==.Toastz:BAAALgAECgEJAQAAAA==.Tokken:BAACLgAFFH8PAAICAAQJXxKDFQApAQACAAQJXxKDFQApAQAuAAQKfyIAAgIACQnpHEcMAPYCAAIACQnpHEcMAPYCAAAA.',
Tr='Treebeast:BAACLgAFFH8GAAIJAAMJDROBFwCXAAAJAAMJDROBFwCXAAAuAAQKfxUAAgkABwlnH4kcAC0CAAkABwlnH4kcAC0CAAAA.Troile:BAAALgADCgkJEQAAAA==.Trojen:BAAALgADCgcJBwAAAA==.Trolladin:BAAALgAECgEJAQABLgAECgUJBgAGAAAAAA==.',
Tu='Tubularoso:BAABLgAECn8WAAIVAAcJ7g+5DAAmAQAVAAcJ7g+5DAAmAQAAAA==.Tupacalypse:BAAALgAECgEJAQAAAA==.',
Tw='Twobtn:BAAALgAECgUJBQAAAA==.',
Ty='Tyras:BAAALgADCgYJBgAAAA==.',
Ul='Ulanda:BAABLgAECn8ZAAQBAAYJ1g7ISgAdAQABAAYJ1g7ISgAdAQApAAMJmQI1PgA7AAAPAAEJqwHHjwAcAAAAAA==.',
Um='Umako:BAACLgAFFH8MAAMoAAUJjx6WAQBvAQAoAAQJcyCWAQBvAQAYAAIJAxwqEwCzAAAuAAQKfyEAAygACQmuIfIAAEQDACgACQmUIfIAAEQDABgACAlGFyYdABYCAAAA.',
Un='Underbogg:BAAALgADCgUJBQAAAA==.Unus:BAAALgADCgQJBAABLgAECgkJIwAEAJEdAA==.',
Uu='Uuznarf:BAAALgADCgQJBQAAAA==.',
Ux='Ux:BAAALgAECgcJBwAAAA==.',
Va='Vaedric:BAAALgAECgIJAwAAAA==.Vaelkor:BAAALgADCgEJAQAAAA==.Vainquish:BAAALgAECgQJBQAAAA==.Varynia:BAAALgAECgcJEQAAAA==.Vashtí:BAAALgADCgUJBQAAAA==.',
Ve='Vekki:BAAALgAECgcJBwAAAA==.Vengened:BAACLgAFFH8KAAICAAQJTQd6GwAEAQACAAQJTQd6GwAEAQAuAAQKfx0AAgIACAkRG70nAB8CAAIACAkRG70nAB8CAAAA.Vermena:BAAALgADCgEJAQAAAA==.',
Vg='Vgly:BAAALgADCgMJAwAAAA==.',
Vi='Vijon:BAAALgAECgQJBAAAAA==.Vilous:BAABLgAECn8nAAICAAgJMSbIAwD5AgACAAgJMSbIAwD5AgAAAA==.Vixxan:BAAALgADCgEJAQAAAA==.',
Vo='Voidiablo:BAABLgAECn8cAAIFAAgJew2NVQA3AQAFAAgJew2NVQA3AQAAAA==.Voids:BAAALgADCgcJDAAAAA==.Voìd:BAAALgADCgUJBQAAAA==.',
Vr='Vraax:BAAALgAFFAMJBAAAAA==.',
['Vé']='Vénandi:BAAALgAECgIJAgAAAA==.',
['Vø']='Vødka:BAAALgADCgMJAwABLgAECgUJBgAGAAAAAA==.',
['Vý']='Výce:BAABLgAECn8VAAMXAAgJwBqHIwAKAgAXAAgJwBqHIwAKAgAJAAQJ7AWnXAByAAAAAA==.',
Wa='Walkerwhite:BAAALgAECgkJDwABLgAECggJIQAMAN0ZAA==.Warjd:BAABLgAECn8aAAICAAgJQgxsKABsAQACAAgJQgxsKABsAQAAAA==.Warriors:BAAALgADCgcJBwAAAA==.',
We='Weebo:BAAALgADCgYJCQAAAA==.Wesjin:BAABLgAECn8aAAIbAAkJcRq2DgBrAgAbAAkJcRq2DgBrAgAAAA==.Wez:BAAALgAECgcJDQAAAA==.',
Wh='Whiskee:BAACLgAFFH8OAAInAAQJ8hcZAwBpAQAnAAQJ8hcZAwBpAQAuAAQKfysABCcACQl5I7QEAM0CACcACQl5I7QEAM0CAAEABwn0D2tAAEkBAA8AAQn/E9RjADwAAAAA.',
Wi='Willybob:BAAALgADCgEJAgAAAA==.Wintulyn:BAAALgAECgYJCQAAAA==.Witherfang:BAAALgAECgUJBgAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.Wooglone:BAAALgADCggJFwAAAA==.Wookong:BAAALgADCgUJBQAAAA==.',
Wr='Wrattchild:BAAALgADCgYJBgAAAA==.',
Wy='Wyndia:BAAALgAECgYJCwAAAA==.',
['Wô']='Wôrldsòùl:BAAALgAECgYJCQABLgAECggJJQAjABgVAA==.',
Xb='Xbert:BAAALgAECgMJAwAAAA==.',
Xe='Xenophontes:BAACLgAFFH8VAAIEAAYJxBcgDgCqAQAEAAYJxBcgDgCqAQAuAAQKfxwAAgQACAn+IZIuALgCAAQACAn+IZIuALgCAAAA.Xerlk:BAAALgADCgkJDAAAAA==.',
Xi='Xihuang:BAAALgAECgcJCwABLgAFFAUJBgAEAHEEAA==.Xiia:BAABLgAECn8jAAIhAAkJ3xtQBADhAQAhAAkJ3xtQBADhAQAAAA==.',
Xx='Xxoouu:BAABLgAFFH8KAAIbAAUJbQ1JEgBFAQAbAAUJbQ1JEgBFAQABLgAFFAYJAQAGAAAAAA==.Xxuu:BAAALgAFFAYJAQAAAA==.Xxuublue:BAAALgAFFAYJAQAAAA==.Xxuuvoker:BAAALgAECgkJCQABLgAFFAYJAQAGAAAAAA==.',
Ya='Yaoguai:BAABLgAECn8fAAMPAAkJNhJ6GACyAQAPAAkJNhJ6GACyAQABAAEJwAPE4wAhAAAAAA==.Yasei:BAAALgAECgEJAQAAAA==.Yawgmoth:BAABLgAECn8WAAMeAAkJVhb9BAAiAgAeAAkJVhb9BAAiAgAUAAEJKgy2/wAzAAAAAA==.',
Yd='Ydalflow:BAAALgADCgkJDQAAAA==.',
Za='Zammboomafoo:BAABLgAECn8bAAIdAAYJXyEnCwDAAQAdAAYJXyEnCwDAAQAAAA==.Zanian:BAABLgAECn8YAAMBAAgJghV+JgDWAQABAAgJghV+JgDWAQAnAAIJoAPhLABKAAAAAA==.Zarthie:BAAALgADCgYJBgABLgAECgcJFgAQAMcTAA==.Zarthy:BAABLgAECn8WAAIQAAcJxxO7JACXAQAQAAcJxxO7JACXAQAAAA==.',
Ze='Zeloran:BAAALgADCgMJAwAAAA==.Zephon:BAAALgAECgYJEQAAAA==.Zerra:BAAALgAECgEJAQAAAA==.',
Zh='Zhed:BAAALgADCgQJBAAAAA==.',
Zi='Zip:BAAALgADCgkJCQAAAA==.',
Zo='Zodd:BAAALgADCgEJAgAAAA==.',
Zu='Zukas:BAAALgAECgMJBgAAAA==.Zulthak:BAAALgAECgUJCwABLgAECgkJMwAEAJQjAA==.Zuo:BAAALgAECgMJBAAAAA==.',
Zy='Zyncoffee:BAABLgAECn8ZAAInAAgJMBv3BQCjAgAnAAgJMBv3BQCjAgAAAA==.',
['Zà']='Zàánn:BAABLgAECn8VAAIJAAcJbxCvMgAZAQAJAAcJbxCvMgAZAQAAAA==.',
['Ær']='Æris:BAAALgADCgYJBgAAAA==.',
['Ða']='Ðarkspartan:BAAALgADCgcJDAABLgAFFAQJDgAiAIccAA==.',
['Ðå']='Ðårkspartan:BAAALgADCggJCAABLgAFFAQJDgAiAIccAA==.',
['Öv']='Över:BAAALgADCgIJAgAAAA==.',
['Øl']='Øld:BAAALgAECgUJBgAAAA==.',
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
