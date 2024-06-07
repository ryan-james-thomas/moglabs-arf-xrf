classdef mogtable < handle
    %MOGTABLE Class defintion for handling tables for the MOGLabs ARF DDS
    %unit.
    properties(SetAccess = protected)
        parent          %Parent mogdevice object
        channel         %Channel number
        dataToWrite     %Data to write to device [times,frequencies,powers/amplitudes,phases]
        sync            %Synchronization vector
    end
    
    properties
        t               %Times to use in seconds
        freq            %Frequencies to use in MHz
        pow             %Either RF powers in dBm or 14-bit hexadecimal amplitudes
        phase           %Phase values to write in degrees
        pow_units       %Power units, either ''dBm'' or ''hex''
    end
    
    properties(Constant)
        FREQ_BITS = 32;             %Number of bits in the DDS FTW
        CLK = 1e3;                  %In MHz, so 1 GHz
        MODE = 'TSB';               %This is the simple table mode for the ARF
        POW_OFF_VALUE = -50;        %RF power corresponding to ''off''
        LOW_POW_THRESHOLD = -20;    %RF power below which we set the power to the ''off'' value
    end
    
    methods
        function self = mogtable(parent,channel)
            %MOGTABLE Creates a MOGTABLE object
            %
            %   SELF = MOGTABLE(PARENT,CHANNEL) Creates a MOGTABLE object
            %   with PARENT mogdevice object and associated channel number,
            %   which must be either 1 or 2
            if ~isa(parent,'mogdevice')
                error('Parent must be a ''mogdevice'' object!');
            elseif channel ~= 1 && channel ~= 2
                error('Channel must be either 1 or 2!');
            end
            
            self.parent = parent;
            self.channel = channel;
            self.dataToWrite = [];
            self.pow_units = 'dbm';
        end
        
        function self = check(self)
            %CHECK Checks values to make sure they are within range of the
            %device
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).check;
                end
            else
                %Check times
                if any(diff(self.t*1e6) < 1)
                    if ~any(round(diff(self.t*1e6)) < 1)
%                         warning('Some dt values are less than 1 us, but this may be a floating point error');
                    else
                        error('Time steps must be at least 1 us');
                    end
                end
                %Check frequencies
                if any(self.freq > 400) || any(self.freq < 10)
                    error('Frequencies must be between [10,400] MHz');
                end
                %Check powers
                if strcmpi(self.pow_units,'dbm')
                    if any(self.pow > 35.1)
                        error('Powers must be below 35.1 dBm');
                    end
                    %Coerce low powers
                    self.pow(self.pow < self.LOW_POW_THRESHOLD) = self.POW_OFF_VALUE;
                elseif strcmpi(self.pow_units,'hex')
                    %Check amplitudes
                    if any(self.pow >= 2^14)
                        error('Amplitudes must be less than 2^14');
                    end
                else
                    error('pow_units must be either ''dBm'' or ''hex''');
                end
                %Wrap phase
                self.phase = mod(self.phase,360);
            end
        end
        
        function self = reduce(self,syncin)
            %REDUCE Reduces the number of entries by eliminating entries
            %with RF powers below the cut-off threshold value. This
            %function can only be used when 'pow_units' = 'dBm'
            %
            %   SELF = SELF.REDUCE(); Performs the reduction. Populates the
            %   "sync" property which can be used to synchronize table
            %   entries
            %
            %   SELF = SELF.REDUCE(SYNCIN) Uses SYNCIN to select the
            %   entries to keep.  Used for making sure the two tables have
            %   the exact same number of entries.
            
            if nargin == 1
                syncin = [];
            end
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).reduce(syncin);
                end
            else
                self.check;
                if strcmpi(self.pow_units,'hex')
                    error('Power units must be set to dBm to use this mode!');
                end
                %
                % Expand values
                %
                self.dataToWrite = [self.t(1),self.pow(1),self.freq(1),self.phase(1)];
                N = numel(self.t);
                t2 = expand(self.t,N);
                p2 = expand(self.pow,N);
                f2 = expand(self.freq,N);
                ph2 = expand(self.phase,N);
                
                if ~isempty(syncin)
                    %
                    % If SYNCIN is provided, then only select entries where
                    % SYNCIN = 1
                    %
                    self.dataToWrite = [self.t(syncin),self.pow(syncin),self.freq(syncin),self.phase(syncin)];
                else
                    %
                    % If no SYNCIN is provided, remove entries that are
                    % below the LOW_POW_THRESHOLD.
                    %
                    mm = 1;
                    self.sync = false(N,1);
                    self.sync(1) = true;
                    for nn = 2:N
                        if nn < N && p2(nn) >= self.LOW_POW_THRESHOLD && p2(nn+1) < self.LOW_POW_THRESHOLD
                            %
                            % This conditional statement makes sure that a
                            % power off value is always included before a
                            % long run of values where the power is too low
                            %
                            self.dataToWrite(mm + 1,:) = [t2(nn),p2(nn),f2(nn),ph2(nn)];
                            self.dataToWrite(mm + 2,:) = [t2(nn),self.POW_OFF_VALUE,f2(nn),ph2(nn)];
                            mm = mm + 2;
                            self.sync([nn,nn + 1]) = true;
                        elseif p2(nn) >= self.LOW_POW_THRESHOLD
                            self.dataToWrite(mm+1,:) = [t2(nn),p2(nn),f2(nn),ph2(nn)];
                            mm = mm + 1;
                            self.sync(nn) = true;
                        end
                    end
                end
            end
        end
        
        function s = createTableString(self)
            %CREATETABLESTRING Creates the string commands necessary for
            %uploading the PARENT mogdevice object.
            %
            %   S = SELF.CREATETABLESTRING() Returns a cell array of
            %   commands to write to the mogdevice object representing the
            %   table entries as well as commands to switch the mode, clear
            %   the table, and arm/rearm the table.
            %
            if numel(self) > 1
                s = {};
                for nn = 1:numel(self)
                    tmp = self(nn).createTableString;
                    s = [s tmp];
                end
            else
                if strcmpi(self.pow_units,'hex')
                    self.dataToWrite = [self.t(:),self.pow(:),self.freq(:),self.phase(:)];
                end
                dt = diff(self.dataToWrite(:,1));
                dt = round(dt(:)*1e6);
                dt(end+1) = 10; %#ok<*NASGU>
                if dt(1) < 2
                    error('First instruction must be longer than 2 us!');
                end
                dt(1) = dt(1) - 2;  %This fixes a 2 us delay in the first instruction
                N = numel(dt);
                if N > 8191
                    error('Maximum number of table entries is 8191');
                end

                s = cell(6 + N,1);
                s{1} = sprintf('mode,%d,%s',self.channel,self.MODE);
                s{2} = sprintf('debounce,%d,off',self.channel);
                s{3} = sprintf('table,stop,%d',self.channel);
                s{4} = sprintf('table,clear,%d',self.channel);
                
                for nn = 1:N
                    f = self.dataToWrite(nn,3);
                    p = self.dataToWrite(nn,2);
                    ph = self.dataToWrite(nn,4);
                    if strcmpi(self.pow_units,'dbm')
                        if p > -45
                            s{nn+4} = sprintf('table,append,%d,%.6f,%.4f,%.6f,%d',...
                                self.channel,f,p,ph,dt(nn));
                        else
                            s{nn+4} = sprintf('table,append,%d,%.6f,0x%04x,%.6f,%d',...
                                self.channel,f,0,ph,dt(nn));
                        end
                    elseif strcmpi(self.pow_units,'hex')
                        s{nn+4} = sprintf('table,append,%d,%.6f,0x%04x,%.6f,%d',...
                                self.channel,f,p,ph,dt(nn));
                    else
                        error('Power units must be either ''dbm'' or ''hex''');
                    end
                end
                s{end - 1} = sprintf('table,arm,%d',self.channel);
                s{end} = sprintf('table,rearm,%d,on',self.channel);
            end
        end
        
        function self = reduce_binary(self)
            %REDUCE_BINARY Reduces binary table data to eliminate entries
            %where the amplitude is 0
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).reduce_binary;
                end
            else        
                self.check;
                if strcmpi(self.pow_units,'dbm')
                    error('Power units must be set to ''hex'' to use this mode!');
                end
                self.dataToWrite = [self.t(1),self.pow(1),self.freq(1),self.phase(1)];
                N = numel(self.t);
                t2 = expand(self.t,N);
                p2 = round(expand(self.pow,N));
                f2 = expand(self.freq,N);
                ph2 = expand(self.phase,N);
                
                mm = 1;
                for nn = 2:N
                    if nn < N && p2(nn) > 0 && p2(nn + 1) == 0
                        self.dataToWrite(mm + 1,:) = [t2(nn),p2(nn),f2(nn),ph2(nn)];
                        self.dataToWrite(mm + 2,:) = [t2(nn + 1),0,f2(nn),ph2(nn)];
                        mm = mm + 2;
                    elseif p2(nn) > 0
                        self.dataToWrite(mm + 1,:) = [t2(nn),p2(nn),f2(nn),ph2(nn)];
                        mm = mm + 1;
                    end
                end    
                self.dataToWrite(end,2) = 0;
            end
        end
        
        function x = make_binary_table(self)
            %MAKE_BINARY_TABLE Creates the binary values necessary for
            %uploading binary tables to the device. This command only works
            %for simple tables with no loops and where only frequency,
            %amplitude, and phase of the DDS are changed.
            %
            %   X = SELF.MAKE_BINARY_TABLE() Creates a vector of uint32
            %   values X which creates the table for this channel.  Each
            %   table entry corresponds to 4 uint32 values.  For N table
            %   entries, X has length 4*(N + 1).  The first set of 4 uint32
            %   values is a table header, the least-significant 16 bits of
            %   which correspond to the number of entries in the table
            %
            if numel(self) > 1
                for nn = 1:numel(self)
                    x(:,nn) = self(nn).make_binary_table;
                end
            else
                self.reduce_binary;
                
                N = size(self.dataToWrite,1);
                dt = diff(self.dataToWrite(:,1));
                dt = round(dt(:)*1e6);
                dt(end+1) = 10;
                if dt(1) < 2
                    error('First instruction must be longer than 2 us!');
                end
                dt(1) = dt(1) - 2;  %This fixes a 2 us delay in the first instruction
                x = zeros(4*N,1,'uint32');
                for nn = 1:N
                    if nn == N
                        %The last entry has this flag set in the command
                        %word
                        cmd_inst = bitshift(uint32(1),31);
                    else
                        cmd_inst = uint32(0);
                    end
                    delay_inst = uint32(dt(nn));
                    amp_inst = uint32(self.dataToWrite(nn,2));
                    phase_inst = uint32(mod(self.dataToWrite(nn,4),360)/360*2^16);
                    freq_inst = uint32(self.dataToWrite(nn,3)/self.CLK*2^32);
                    %
                    % Create binary table
                    %
                    x((nn-1)*4 + 1) = byte_swap(cmd_inst);
                    x((nn-1)*4 + 2) = byte_swap(delay_inst);
                    x((nn-1)*4 + 3) = byte_swap(bitshift(amp_inst,16) + phase_inst);
                    x((nn-1)*4 + 4) = byte_swap(freq_inst);
                end
                %
                % Add the header to the beginning of the table
                %
                x_header = zeros(4,1,'uint32');
                x_header(1) = 2^16 + uint32(N);
                x = [x_header;x];
            end
        end
        
        function upload_binary_table(self,x)
            %UPLOAD_BINARY_TABLE Uploads a binary table.  Uses normal
            %text-based commands to set the table mode, clear the table,
            %and arm the table, but the table entries are sent as binary
            %values.
            %
            %   SELF.UPLOAD_BINARY_TABLE() Creates the binary table using
            %   object data and uploads it.
            %
            %   SELF.UPLOAD_BINARY_TABLE(X) Uploads the binary table
            %   represented by the vector X.  No checking is done on the
            %   input, so make sure it's correct!
            if nargin == 1
                x = self.make_binary_table;
            else
                x = uint32(x);
            end
            
            self.parent.cmd('mode,%d,%s',self.channel,self.MODE);
            self.parent.cmd('debounce,%d,off',self.channel);
            self.parent.cmd('table,stop,%d',self.channel);
            self.parent.cmd('table,clear,%d',self.channel);
            self.parent.cmd('table,upload,%d,%d',self.channel,round(numel(x)*4));
            self.parent.send_raw(typecast(uint32(x),'uint8'));
            self.parent.cmd('table,arm,%d',self.channel);
            self.parent.cmd('table,rearm,%d,on',self.channel);
            
        end
        
        function numInstr = upload(self)
            %UPLOAD Uploads a table using only text-based commands. Uses
            %the mogdevice.uploadCommands() function, which is
            %asynchronous.
            commands = self.createTableString;
            commands = commands(:);
            for nn = 1:2
                commands{end+1} = sprintf('table,arm,%d',nn); %#ok<*AGROW>
                commands{end+1} = sprintf('table,rearm,%d,on',nn);
            end
%             commands{end+1} = 'table,sync,1';
            numInstr = numel(commands);
            self(1).parent.uploadCommands(commands(:));
        end
        
        function self = start(self)
            %START Starts table execution.
            r = self.parent.cmd('table,start,%d',self.channel);
            disp(r);
        end
        
        function self = arm(self)
            %ARM Arms the current table.
            if numel(self) > 1
                for nn = 1:numel(self)
                    self(nn).arm;
                end
            else
                self.parent.cmd('table,arm,%d',self.channel);
                self.parent.cmd('table,rearm,%d,on',self.channel);
            end
        end
        
    end
    
    methods(Static)
        function rf = opticalToRF(P,Pmax,rfmax)
            rf = (asin((P/Pmax).^0.25)*2/pi).^2*rfmax;
        end
    end
    
end

function r = expand(v,N)
    if numel(v) == 1
        r = v*ones(N,1);
    else
        r = v;
    end
end

function r = byte_swap(xin)
    x2 = typecast(uint32(xin),'uint16');
    r = typecast(x2([2,1]),'uint32');
end